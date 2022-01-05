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

    config_objects.each_with_index.map { |lookup, index|
      lookup.keys.each do |key|
        m = key.match(/(name|lookup_values)_(.*)/)
        next unless m
        new_key = m[1].to_s.concat('_i18n')
        lang = m[2].gsub('_', '-')
        if new_key == 'name_i18n'
          config_objects[index][new_key] = {} unless config_objects[index].has_key?(new_key)
          config_objects[index][new_key][lang] = config_objects[index][key].nil? ? "" : config_objects[index].delete(key)
        elsif new_key == 'lookup_values_i18n'
          lookup_values = config_objects[index].delete(key)
          next unless lookup_values

          if !config_objects[index].key?(new_key)
            config_objects[index][new_key] = []
          end

          lookup_values.each do |value|
            value_index = config_objects[index][new_key].index { |item| item['id'] == value['id'] }
            if value_index.nil?
              new_value = {}
              new_value['id'] = value['id']
              new_value['display_text'] = {}
              new_value['display_text'][lang] = value['display_text']

              config_objects[index][new_key].append(new_value)
            else
              config_objects[index][new_key][value_index]['display_text'][lang] = value['display_text']
            end
          end
        end
      end
    }


    config_objects + default_lookups
  end

  def config_object_names
    %w[Lookup]
  end
end
