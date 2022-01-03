# frozen_string_literal: true

require_relative('configuration_exporter.rb')

# Exports the current v1 state of the Primero forms configuration as v2 compatible Ruby scripts.
class FormConfigExporter < ConfigurationExporter
  def export
    forms_with_subforms.each do |_, form_with_subforms|
      forms_hash = form_with_subforms.map { |form| configuration_hash_form_section(form) }
      puts "Exporting Form #{forms_hash.first['unique_id']}"
      export_config_objects('FormSection', forms_hash)
    end
  end

  private

  def file_for(opts = {})
    return if opts[:config_objects].blank?

    config_dir = "#{@export_dir}/forms/#{opts[:config_objects].last['parent_form']}"
    FileUtils.mkdir_p(config_dir)
    "#{config_dir}/#{opts[:config_objects].last['unique_id']}.rb"
  end

  def default_service_referral_fields
    [
      {
        'name' => 'service_external_referral',
        'type' => 'tick_box',
        'tick_box_label_en' => 'Yes',
        'visible' => false,
        'display_name' => {
          'en' =>  'Is this a referral to an external system / user?'
        }
      },
      {
        'name' => 'service_external_referral_header',
        'type' => 'separator',
        'visible' => false,
        'display_name' => {
          'en' => 'External referral details'
        }
      },
      {
        'name' => 'service_provider',
        'type' => 'text_field',
        'visible' => false,
        'display_name' => {
          'en' => 'Service Provider'
        }
      },
      {
        'name' => 'service_implementing_agency_external',
        'type' => 'text_field',
        'visible' => false,
        'display_name' => {
          'en' => 'Implementing Agency'
        }
      },
      {
        'name' => 'service_location',
        'type' => 'text_field',
        'visible' => false,
        'display_name' => {
          'en' => 'Service Location'
        }
      }
    ]
  end

  def service_referral_fields(field_attributes)
    field_names = field_attributes.map { |f| f['name'] }
    default_service_referral_fields.select { |field| field_names.exclude?(field['name']) }
  end

  def configuration_hash_form_section(object)
    config_hash = object.attributes.except('id', 'fields', 'base_language', 'collapsed_fields', 'fixed_order',
                                           'perm_visible', 'perm_enabled', 'validations')

    translation_fields = [
      'description_',
      'display_name_',
      'guiding_questions_',
      'help_text_',
      'name_',
      'option_strings_text_',
      'tick_box_label_'
    ]
    config_hash.keys.each do |k|
      translation_fields.each do |t|
        new_key = t.dup
        new_key.concat('i18n')
        m = k.match(/#{t}(.*)/)
        if  m
          lang = m[1].gsub('_', '-')
          config_hash[new_key] = {} unless config_hash.has_key?(new_key)
          config_hash[new_key][lang] = config_hash[k].nil? ? "" : config_hash.delete(k)
        end
      end
    end

    config_hash['collapsed_field_names'] = replace_renamed_field_names(object.collapsed_fields) if object.collapsed_fields.present?
    config_hash['fields_attributes'] = object.fields.map do |field|
      configuration_hash_field(field, object.unique_id)
    end
    return config_hash unless config_hash['unique_id'] == 'services_section'

    config_hash['fields_attributes'] += service_referral_fields(config_hash['fields_attributes'])
    config_hash
  end

  def configuration_hash_field_name(config_hash)
    config_hash['name'] = config_hash['name'].gsub(/bia/, 'assessment') if config_hash['name'].include?('bia_approved')
    config_hash['name'] = renamed_fields[config_hash['name']] if renamed_fields.keys.include?(config_hash['name'])
    config_hash
  end

  def configuration_hash_field(field, form_unique_id)
    config_hash = field.attributes.except('id', 'highlight_information', 'base_language', 'deletable',
                                          'searchable_select', 'create_property',
                                          'subform_section_id').with_indifferent_access
    config_hash['subform_unique_id'] = field.subform_section_id if field.type == 'subform'
    config_hash['disabled'] = false if field.type.include?('upload_box')
    config_hash['option_strings_source'] = field.option_strings_source.split(' ').first if field.option_strings_source&.include?('use_api')
    config_hash = configuration_hash_field_name(config_hash)
    config_hash
  end
end
