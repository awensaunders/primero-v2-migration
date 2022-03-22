# frozen_string_literal: true

require_relative('configuration_exporter.rb')

# Exports the current v1.7 or v1.6 state of the Primero configuration as v2 compatible Ruby scripts.
class BaseConfigExporter < ConfigurationExporter
  private

  def generate_report_id(name)
    code = UUIDTools::UUID.random_create.to_s.last(7)
    "#{name.parameterize}-#{code}"
  end

  def convert_field_map(field_map)
    return field_map if field_map['fields'].blank?

    field_map['fields'] = field_map['fields'].map do |f|
      { 'source' => f['source'].last, 'target' => f['target'] } if f['source'].first != 'incident_details'
    end.compact
    field_map
  end

  def form_section_ruby_string(form_ids)
    "FormSection.where(unique_id: %w#{form_ids})".delete('\"').delete(',')
  end

  def primero_program_ruby_string(program_id)
    "PrimeroProgram.find_by(unique_id: '#{program_id}')"
  end

  def primero_module_options(object)
    {
      agency_code_indicator: object.agency_code_indicator,
      workflow_status_indicator: object.workflow_status_indicator,
      allow_searchable_ids: object.allow_searchable_ids,
      selectable_approval_types: object.selectable_approval_types,
      use_workflow_service_implemented: object.use_workflow_service_implemented,
      use_workflow_case_plan: object.use_workflow_case_plan,
      use_workflow_assessment: object.use_workflow_assessment,
      reporting_location_filter: object.reporting_location_filter,
      user_group_filter: object.user_group_filter
    }
  end

  def configuration_hash_agency(object)
    object.attributes.except('id', 'base_language', 'core_resource', '_attachments').merge(unique_id(object)).with_indifferent_access
  end

  def configuration_hash_report(object)
    config_hash = object.attributes.except('id', 'module_ids', 'exclude_empty_rows', 'base_language',
                                           'primero_version').with_indifferent_access
    config_hash['module_id'] = object.module_ids.first
    config_hash['unique_id'] = generate_report_id(object.name_en)
    config_hash['aggregate_by'] = replace_renamed_field_names(object.aggregate_by) if object.aggregate_by.present?
    config_hash['disaggregate_by'] = replace_renamed_field_names(object.disaggregate_by) if object.disaggregate_by.present?
    config_hash
  end

  def configuration_hash_user_group(object)
    object.attributes.except('id').merge(unique_id(object)).with_indifferent_access
  end

  def configuration_hash_primero_module(object)
    config_hash = object.attributes.except('id', 'associated_form_ids', 'field_map', 'program_id',
                                           'agency_code_indicator', 'workflow_status_indicator', 'allow_searchable_ids',
                                           'selectable_approval_types', 'use_workflow_service_implemented',
                                           'use_workflow_case_plan', 'use_workflow_assessment',
                                           'reporting_location_filter',
                                           'user_group_filter').merge(unique_id(object)).with_indifferent_access
    config_hash['field_map'] = convert_field_map(object.field_map)
    config_hash['module_options'] = primero_module_options(object)
    config_hash['form_sections'] = form_section_ruby_string(object.associated_form_ids - retired_forms)
    config_hash['primero_program'] = primero_program_ruby_string(object.program_id)

    config_hash
  end

  def configuration_hash_primero_program(object)
    config_hash = object.attributes.except('id', 'name', 'description').merge(unique_id(object)).with_indifferent_access
    config_hash['name_en'] = object.name
    config_hash['description_en'] = object.description
    config_hash
  end

  def configuration_hash_contact_information(object)
    config_hash = object.attributes.except('id').with_indifferent_access
    config_hash[:name] ||= 'administrator'
    config_hash
  end

  def configuration_hash_export_configuration(object)
    config_hash = object.attributes.except('id').with_indifferent_access
    config_hash['unique_id'] = "export-#{object.export_id.dasherize if object && object.export_id}"
    config_hash
  end

  def config_object_names
    %w[Agency Report UserGroup PrimeroModule PrimeroProgram ContactInformation ExportConfiguration]
  end
end
