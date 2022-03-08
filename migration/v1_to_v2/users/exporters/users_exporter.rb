# frozen_string_literal: true

# Generates a v2.0+ compatible script to create users.
class UsersExporter
  # rubocop:disable Style/StringLiterals, Style/RedundantBegin

  HEADER = [
    "# Automatically generated script to migrate users from v1.7 to v2.0+\n"
  ].join("\n").freeze

  CREATE_METHOD = [
    "def create_or_update_user(user_hash)",
    "  user = User.find_by(user_name: user_hash[:user_name])",
    "  if user.present?",
    "    user.assign_attributes(user_hash)",
    "  else",
    "    user = User.new(user_hash)",
    "  end",
    "  random_password = \"\#{SecureRandom.base64(40)}1a\"",
    "  user.password = random_password",
    "  user.password_confirmation = random_password",
    "  puts \"Saving user: \#{user.user_name}...\"",
    "  user.save!\n",
    "  if @send_reset_email",
    "    user.send_reset_password_instructions",
    "    user.send_welcome_email(@admin_user) if @admin_user.present? ",
    "  end",
    "rescue ActiveRecord::RecordNotUnique",
    "  puts \"Skipping creation of user \#{user.user_name}. User already exists.\"",
    "rescue StandardError => e",
    "  puts \"Error creating user: \#{user.user_name}\"",
    "  puts e",
    "end\n\n"
  ].join("\n").freeze

  BEGIN_ARRAY = "@users = [\n"

  END_ARRAY = "]\n\n"

  ENDING = [
    "@users.each{ |user| create_or_update_user(user) }\n"
  ].join("\n").freeze

  NULLABLE_USER_FIELD_NAMES = %i[code phone agency_office position location user_group_ids locale].freeze

  def initialize(options = {})
    @export_dir = options[:export_dir] || 'seed-files'
    @config_dir = "#{@export_dir}/users"
    @config_file = "#{@config_dir}/users.rb"
    @batch_size = options[:batch_size] || 500
    @send_reset_email = options[:send_reset_email] == 'true' || options[:send_reset_email] == true
    @admin_user_name = options[:admin_user_name]
    @log = options[:log] || fallback_logger
    @locale_hash = options[:locale_hash] || {}
  end

  def export
    FileUtils.mkdir_p(@config_dir)
    File.open(@config_file, 'a+') do |file|
      begin
        write_beginning(file)
        User.each_slice(@batch_size) { |batch| write_batch(file, batch) }
        write_batch(file, [migration_system_user])
        write_ending(file)
      rescue StandardError => e
        @log.error(e)
      end
    end
  end

  private

  def fallback_logger
    timestamp = DateTime.now.strftime('%Y%m%d.%I%M')
    log_filename = "user-exporter-logs-#{timestamp}.txt"
    log = Logger.new(log_filename)
    log.formatter = proc do |severity, _, _, msg|
      "#{severity}: #{msg}\n"
    end
    log
  end

  def write_beginning(file)
    file.write(HEADER)
    file.write(CREATE_METHOD)
    file.write(build_initializers)
    file.write(build_admin_user)
    file.write(BEGIN_ARRAY)
  end

  def write_ending(file)
    file.write(END_ARRAY)
    file.write(ENDING)
  end

  def build_initializers
    [
      "@agencies = Agency.all.reduce({}){ |acc, elem| acc.merge({ elem.unique_id => elem }) }",
      "@user_groups = UserGroup.all.reduce({}){ |acc, elem| acc.merge({ elem.unique_id => elem }) }",
      "@roles = Role.all.reduce({}){ |acc, elem| acc.merge({ elem.unique_id => elem }) }",
      "@send_reset_email = #{@send_reset_email}\n",
      "puts 'send_reset_password_instructions will be skipped because send_reset_email is not enabled.' if !@send_reset_email \n\n"
    ].join("\n").freeze
  end

  def build_admin_user
    if @admin_user_name.blank?
      return "puts 'send_welcome_email will be skipped because the admin_user_name is not defined.'\n\n"
    end

    admin_user = User.find_by_user_name(@admin_user_name)

    return admin_user_string(admin_user) if admin_user.present?

    @log.warn("Admin user: #{@admin_user_name} was not found.")

    "puts 'send_welcome_email will be skipped because the admin user: #{@admin_user_name} was not found.'\n"
  end

  def admin_user_string(admin_user)
    [
      "puts 'Creating admin user: #{@admin_user_name}...'",
      "@admin_user = #{stringify_user(admin_user)[0..-3]}",
      "create_or_update_user(@admin_user)",
      "if @admin_user.persisted?",
      "  @admin_user.reload",
      "else",
      "  puts 'send_welcome_email will be skipped because the admin user: #{@admin_user_name} was not created.'",
      "end\n\n"
    ].join("\n")
  end

  def migration_system_user
    password = SecureRandom.base64(40)
    User.new(
      user_name: 'migration_system_user',
      password: password,
      password_confirmation: password,
      full_name: 'Migration System User',
      send_mail: 'false',
      disabled: 'true',
      organization: Agency.all.select{|agency| agency.name_en == 'UNICEF'}.first.id,
      role_ids: [Role.by_name(key: "Superuser").first.id],
      module_ids: PrimeroModule.all.map(&:id),
      user_group_ids: UserGroup.all.map(&:id)
    )
  end

  def write_batch(file, batch)
    batch.each do |user|
      next if user.user_name == @admin_user_name

      user = migrate_user_locale(user) if @locale_hash.present?
      begin
        file.write(stringify_user(user))
        @log.info("User: #{user.user_name} written successfully")
      rescue StandardError => e
        @log.error(e)
        @log.error("Error when user: #{user.user_name} was written")
      end
    end
  end

  def migrate_user_locale(user)
    if @locale_hash.present? || user.locale.present?
      user.locale = @locale_hash[user.locale] || user.locale
    end
    user
  end

  def stringify_user(user)
    email = user.email.present? ? user.email : "#{user.user_name}@primero.org"
    [
      "  {",
      "    user_name: \"#{user.user_name}\",",
      "    full_name: \"#{user.full_name}\",",
      "    email: \"#{email}\",",
      "    disabled: #{user.disabled},",
      "    agency_id: @agencies[\"#{user.organization}\"]&.id,",
      "    role_id: @roles[\"#{user.roles.first.id}\"]&.id,",
      "    time_zone: \"#{user.time_zone || 'UTC'}\",",
      "    send_mail: #{user.send_mail},",
      "    services: #{user.services},",
      stringify_nullable_fields(user),
      "  },\n"
    ].join("\n")
  end

  def stringify_nullable_fields(user)
    NULLABLE_USER_FIELD_NAMES.map do |field_name|
      field_value = user.send(field_name)

      next unless field_value.present?

      case field_name
      when :user_group_ids
        "    user_groups: #{field_value}.map { |unique_id| @user_groups[unique_id] }.compact,"
      when :location
        "    #{field_name}: \"#{field_value.gsub(/[^0-9A-Za-z]/, '')}\","
      else
        "    #{field_name}: \"#{field_value}\","
      end
    end.compact.join("\n")
  end

  # rubocop:enable Style/StringLiterals, Style/RedundantBegin
end
