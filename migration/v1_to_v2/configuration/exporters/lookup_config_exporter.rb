# frozen_string_literal: true

require_relative('configuration_exporter.rb')

# Exports the current v1 state of the Primero roles configuration as v2 compatible Ruby scripts.
class LookupConfigExporter < ConfigurationExporter
  private

  def lookup_pdf_header
    {
      unique_id: 'lookup-pdf-header',
      name_i18n: { en: 'PDF Header' },
      locked: true,
      lookup_values_i18n: [
        { id: 'pdf_header_1', display_text: { en: 'PDF Header 1' } },
        { id: 'pdf_header_2', display_text: { en: 'PDF Header 2' } },
        { id: 'pdf_header_3', display_text: { en: 'PDF Header 3' } }
      ]
    }
  end

  def default_lookups
    %w[pdf_header].map { |lookup_name| send("lookup_#{lookup_name}") }
  end

  def configuration_hash_lookup(object)
    object.attributes.except('id', 'base_language', 'editable').merge(unique_id(object)).with_indifferent_access
  end

  def config_objects(_config_name)
    config_objects = Lookup.all.map { |object| configuration_hash_lookup(object) }
    migrate_config_translation_fields(config_objects)
    config_objects + default_lookups
  end

  def config_object_names
    %w[Lookup]
  end
end
