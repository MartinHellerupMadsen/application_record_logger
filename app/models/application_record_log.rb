class ApplicationRecordLog < ApplicationRecord
  # self.table_name = 'application_record_logs'
  skip_callback :after_create
  skip_callback :after_update
  skip_callback :after_destroy

  def self.log_create
    false
  end

  def self.log_update
    false
  end

  def self.log_destroy
    false
  end

  belongs_to :owner, polymorphic: true, optional: false
  belongs_to :user, optional: true
  serialize :data
  enum :action => {
    :db_create  => 0,
    :db_update  => 1,
    :db_destroy => 2,
  }

  def self.log(record:, user:, action:)
    if record && (record.saved_changes? || record.destroyed?)
      user_id = user.respond_to?(:id) ? user.id : user
      if action == :db_create
        data = (record.class.log_create_data ||  where(owner: record, action: :db_create).any?) ? record.logging_data : nil
      elsif action == :db_destroy
        data = record.attributes.map do |key, value|
          [key, [value, nil]]
        end.to_h.slice(*record.class.log_fields)
      else
        data = record.logging_data
      end
      create_parms = {           
        owner: record,
        data: data,
        action: action,
      }
      create_parms[:user_id] = user_id if user_id

      if ((data && data.length > 0) || action == :db_create)
        create create_parms
      end
    end
  end

  def self.rollback(owner:, owner_type:, owner_id:, timepoint:, step:)
    klass       = owner_type.constantize
    given_owner = owner
    given_owner ||= klass.find_by(id: owner_id)
    given_owner ||= klass.new(id: owner_id)
    logs = if step
      where(
        owner: owner,
      ).order(:updated_at => :desc).limit(step)
    else
      where(
        owner: owner,
        updated_at: timepoint..(DateTime::Infinity.new)
      ).order(:updated_at => :desc)
    end
    if timepoint && (timepoint < where(owner: owner).minimum(:updated_at))
      return klass.new(id: owner_id)
    else
      logs.each do |log|
        (log.data||{}).each do |key, arr|
          given_owner.send("#{key}=", arr[0])
        end
      end
      given_owner
    end
  end

  def self.rollback!(**kwargs)
    rollback(**kwargs).save
  end
end
