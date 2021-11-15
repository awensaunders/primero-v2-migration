# frozen_string_literal: true

# Script to call each of the Data Exporters
require_relative('exporters/record_data_exporter.rb')
require_relative('exporters/alerts_exporter.rb')
require_relative('exporters/attachment_exporter.rb')
require_relative('exporters/flags_exporter.rb')
require_relative('exporters/linked_incident_data_exporter.rb')
require_relative('exporters/record_histories_exporter.rb')
require_relative('exporters/transition_data_exporter.rb')
require_relative('exporters/traces_exporter.rb')

def exporters
  %w[RecordDataExporter AlertsExporter AttachmentExporter FlagsExporter LinkedIncidentDataExporter
     RecordHistoriesExporter TransitionDataExporter TracesExporter].freeze
end

timestamp = DateTime.now.strftime('%Y%m%d%H%M%S')
export_dir = "record-data-files-#{timestamp}"
exporters.each do |exporter|
  data_exporter = Object.const_get(exporter).new
  data_exporter.export
end

