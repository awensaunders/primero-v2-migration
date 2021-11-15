# frozen_string_literal: true

require_relative('data_exporter.rb')
require 'erb'

# rubocop:disable Metrics/ClassLength
# Class that get record's attachments and generate files to be inserted
class AttachmentExporter < DataExporter
  ATTACHMENTS_FORMS = {
    'case' => %w[photo_keys bia_documents bid_documents other_documents],
    'tracing_request' => []
  }.freeze

  FIELD_MAPPING = {
    'audio_attachments' => 'recorded_audio',
    'photo_keys' => 'photos',
    'bia_documents' => 'upload_bia_document',
    'bid_documents' => 'upload_bid_document',
    'other_documents' => 'other_documents'
  }.freeze

  def initialize(options = {})
    super(options)
    @indent = 0
    @json_to_export = {}
  end

  private

  def data_object_names
    %w[case tracing_request]
  end

  def export_data_objects(object_name)
    @record_type = object_query(object_name.camelize)
    forms = ATTACHMENTS_FORMS[object_name]

    return if forms.empty? || @record_type.count.zero?

    type_folder = "#{object_name.underscore}_attachments"
    @folder_to_save = "#{@export_dir}/#{type_folder}"

    FileUtils.mkdir_p(@folder_to_save)

    puts "Exporting #{@record_type.count} #{object_name.pluralize}"
    export_records(forms, object_name, @folder_to_save)
  end

  def header
    "# Automatically generated script to migrate attachment from v1.7 to v2.0+\n"
  end

  def set_record_id(type, record_id)
    @record_id = uuid_format(record_id)
    @json_to_export[type][@record_id] = {}
  end

  def export_records(forms, type, folder_to_save)
    @record_type.each_slice(@batch_size) do |records|
      @json_to_export[type] = {}
      records.each do |record|
        next if record&._attachments&.empty?

        set_record_id(type, record._id)
        export_forms_attachments(forms, record, folder_to_save, type)
      end
      build_file(folder_to_save, type, _i)
    end
  end

  def export_forms_attachments(forms, record, folder_to_save, type)
    forms.each do |form|
      files = get_files_to_export(record.send(form), form)
      next if files.empty?

      puts "Exporting #{form} from #{type} - #{@record_id}"
      build_data_to_attach(files, folder_to_save, type, form)
      export_file(files, folder_to_save, record, form)
    end
  end

  def get_files_to_export(files, form)
    return [] if files.empty?

    return { files.values.last => "#{files.values.last}.#{files.keys.last}" } if form == 'audio_attachments'

    return files.reduce({}) { |acc, doc| acc.merge(doc => doc) } if form == 'photo_keys'

    files.reduce({}) { |acc, doc| acc.merge(doc.attachment_key => doc) }
  end

  def build_data_to_attach(files, folder, type, form)
    @json_to_export[type][@record_id][form] = []
    files.each do |_key, value|
      name = value.is_a?(String) ? value : value.file_name

      @json_to_export[type][@record_id][form] << {
        record_type: @record_type.to_s, record_id: @record_id, field_name: form,
        file_name: name, date: value.try(:date), comments: value.try(:comments),
        is_current: value.try(:is_current) || false, description: value.try(:document_description),
        path: "/#{@record_id}/#{form}/#{name}"
      }
    end
  end

  def export_file(files, folder, record_data, form)
    files.each do |key, value|
      name = value.is_a?(String) ? value : value.file_name
      path_folder = "#{folder}/#{@record_id}/#{form}"

      FileUtils.mkdir_p(path_folder)
      File.open("#{path_folder}/#{name}", 'wb') do |f|
        begin
          f.write(record_data.fetch_attachment(key))
        rescue StandardError => e
          puts "attachement #{key}  for record #{record_data.id} couldnot be exported due to #{e}"
        end
      end
    end
  end

  def get_field_name(attachement_form)
    FIELD_MAPPING[attachement_form]
  end

  def mime_type(path)
    p2 = @folder_to_save + path.gsub(/ /, '\ ')
    `file --brief --mime-type "#{p2}"`.strip
  end

  def get_attachment_type(path)
    mime = mime_type(path)
    return 'audio' if mime.start_with?('audio')
    return 'image' if mime.start_with?('image')

    'document'
  end

  def initialize_script_for_attachment(folder_to_save, type, sufix)
    script_name = "#{type.pluralize}.#{sufix}.rb"
    @output = File.new("#{folder_to_save}/#{script_name}", 'w')
    @output.puts(header)
    puts "Generating #{script_name} for #{type} - #{@record_id}"
  end

  def add_attachment_type_to_file_for_attachment(path)
    @output.puts "attachement.attachment_type = '#{get_attachment_type(path)}'"
  end

  def add_date_to_file_for_attachment(date)
    return unless date.present?

    @output.puts "attachement.date = \"#{date.strftime('%Y-%m-%d')}\""
  end

  ATTACHMENT_IMPORTER_TEMPLATE = ERB.new(<<~RUBY)
    puts "Inserting <%= get_attachment_type(data[:path]) %> to <%= data[:record_id] >"
    attachement = Attachment.new(<%= data.except(:path, :field_name, :date) %>)
    <% if date.present? %>attachement.date = "<%= date.strftime('%Y-%m-%d') %>"<% end %>
    attachement.record_type = <%= data[:record_type] %>
    attachement.attachment_type = "<%= get_attachment_type(path) %>"
    attachement.field_name = "<%= get_field_name(form_name) %>"
    attachement.file.attach(io: File.open("\#{File.dirname(__FILE__)}<%= data[:path] %>"), filename: <%= data[:file_name].inspect %>)
    begin
      attachement.save!
    rescue StandardError => e
      puts "Cannot attach <%= data[:file_name].inspect %>. Error \#{e.message}"
    end

  RUBY

   def build_file(folder_to_save, type, sufix)
     initialize_script_for_attachment(folder_to_save, type, sufix)

     attachments = []
     data_object_names.each do |type|
       records = @json_to_export[type]

       next if records.blank?

       records.values.each do |form|
         form.each do |form_name, files|
           next if files.nil?

           attachments.push(*files.map { |file| [form_name, file] })
         end
       end
     end


     attachments.each_slice(10) do |slice|
       slice.each do |form, file|
         @output.puts ATTACHMENT_IMPORTER_TEMPLATE.result(binding)
       end

       @output.puts "# force ruby to gargabe collect here as attachmented files can build up in memory!"
       @output.puts "GC.start"
     end
   end
end
# rubocop:enable Metrics/ClassLength
