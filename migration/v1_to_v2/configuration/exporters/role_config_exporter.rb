# frozen_string_literal: true

require_relative('configuration_exporter.rb')

# Exports the current v1 state of the Primero roles configuration as v2 compatible Ruby scripts.
class RoleConfigExporter < ConfigurationExporter
  def initialize(export_dir: 'seed-files', batch_size: 250)
    super
    @module_hash = PrimeroModule.all.map { |m| [m.id, m] }.to_h
  end

  private

  def config_to_ruby_string(config_name, config_hash)
    ruby_string = super
    return ruby_string unless config_hash['form_section_read_write'].nil?

    # The nil is necessary to distinguish between roles that have no form restrictions vs roles that have form
    # restrictions, but all of their allowed forms are retired.
    ruby_string + role_form_ruby_string(config_hash['unique_id']) + "\n\n"
  end

  def role_form_ruby_string(role_id)
    "Role.find_by(unique_id: '#{role_id}')&.associate_all_forms"
  end

  def modules_for_superuser
    @module_hash.keys
  end

  def role_module(object)
    return modules_for_superuser if object.id == 'role-superuser'

    return [PrimeroModule::GBV] if object.id.include?('gbv')

    return [PrimeroModule::MRM] if object.id.include?('mrm')

    [PrimeroModule::CP]
  end

  def role_permitted_form_hash(permitted_form_ids)
    # The nil is necessary to distinguish between roles that have no form restrictions vs roles that have form
    # restrictions, but all of their allowed forms are retired.
    permitted_form_ids.present? ? (permitted_form_ids - retired_forms).map { |f| [f, 'rw'] }.to_h : nil
  end

  def role_forms(permitted_form_ids)
    return forms_with_subforms(visible_only: true).select { |k, _| permitted_form_ids.include?(k) } if permitted_form_ids.present?

    forms_with_subforms(visible_only: true)
  end

  def role_form_ids(permitted_form_ids)
    forms = role_forms(permitted_form_ids)
    return [] if forms.blank?

    forms.values.flatten.map(&:unique_id)
  end

  def incident_from_case_cp?(opts = {})
    return false unless opts[:module_unique_ids].include?('primeromodule-cp')

    opts[:role_form_ids].include?('incident_details_container')
  end

  def incident_from_case_gbv?(actions, opts = {})
    return false unless opts[:module_unique_ids].include?('primeromodule-gbv')

    actions.include?('write') && opts[:role_form_ids].include?('action_plan_form')
  end

  def incident_from_case?(actions, opts = {})
    incident_from_case_cp?(opts) || incident_from_case_gbv?(actions, opts)
  end

  def permission_actions_incident_from_case(actions, opts = {})
    return [] unless incident_from_case?(actions, opts)

    new_actions = []
    new_actions << 'view_incident_from_case' if actions.include?('read')
    new_actions << 'incident_from_case' if (actions & %w[create write]).any?
    new_actions
  end

  def permission_actions_case_close_reopen(actions, opts = {})
    return [] unless actions.include?('write')

    opts[:role_form_ids].include?('basic_identity') ? %w[close reopen] : []
  end

  def permission_actions_case_form_dependent(actions, opts = {})
    return [] if opts[:role_form_ids].blank?

    new_actions = []
    new_actions << 'view_photo' if opts[:role_form_ids].include?('photos_and_audio')
    new_actions += permission_actions_case_close_reopen(actions, opts)
    new_actions += permission_actions_incident_from_case(actions, opts)
    new_actions
  end

  def permission_actions_case(actions, opts = {})
    return [] if actions.blank?

    new_actions = actions - %w[export_case_pdf export_child_pdf request_approval_bia approve_bia]
    new_actions << 'export_pdf' if (actions & %w[export_case_pdf export_child_pdf]).any?
    new_actions << 'request_approval_assessment' if actions.include?('request_approval_bia')
    new_actions << 'approve_assessment' if actions.include?('approve_bia')
    new_actions << 'enable_disable' if actions.include?('write')
    new_actions << 'change_log' if opts[:permitted_form_ids].blank?
    new_actions += permission_actions_case_form_dependent(actions, opts)
    new_actions.uniq
  end

  def permission_actions_incident(actions, opts = {})
    return [] if actions.blank?

    new_actions = actions - %w[export_photowall export_unhcr_csv assign request_approval_bia request_approval_case_plan
                               request_approval_closure]
    new_actions << 'enable_disable' if actions.include?('write')
    new_actions << 'change_log' if opts[:permitted_form_ids].blank?
    new_actions.uniq
  end

  def permission_actions_tracing_request(actions, opts = {})
    return [] if actions.blank?

    new_actions = actions - %w[export_photowall export_unhcr_csv assign export_xls]
    new_actions << 'enable_disable' if actions.include?('write')
    new_actions << 'change_log' if opts[:permitted_form_ids].blank?
    new_actions.uniq
  end

  def receive_permissions?(actions)
    return [] if actions.blank?

    (actions & %w[receive_referral receive_transfer]).any?
  end

  def share_permissions?(actions)
    return [] if actions.blank?

    (actions & %w[referral transfer referral_from_service]).any?
  end

  def permission_actions_dashboard_approval(opts = {})
    return [] unless opts.key?(:case_permissions)
    actions = []
    actions << 'approvals_assessment' if opts[:case_permissions].include?('request_approval_bia')
    actions << 'approvals_assessment_pending' if opts[:case_permissions].include?('approve_bia')
    actions << 'approvals_case_plan' if opts[:case_permissions].include?('request_approval_case_plan')
    actions << 'approvals_case_plan_pending' if opts[:case_permissions].include?('approve_case_plan')
    actions << 'approvals_closure' if opts[:case_permissions].include?('request_approval_closure')
    actions << 'approvals_closure_pending' if opts[:case_permissions].include?('approve_closure')
    actions
  end

  def permission_task_overdue_services?(field_names)
    (!system_settings.due_date_from_appointment_date && field_names.include?('service_response_timeframe')) ||
      (system_settings.due_date_from_appointment_date && field_names.include?('service_appointment_date'))
  end

  def permission_actions_dashboard_task_overdue(actions, field_names)
    return [] if field_names.blank? || actions.exclude?('dash_cases_by_task_overdue')

    new_actions = []
    new_actions << 'cases_by_task_overdue_assessment' if field_names.include?('assessment_requested_on')
    new_actions << 'cases_by_task_overdue_case_plan' if field_names.include?('case_plan_due_date')
    new_actions << 'cases_by_task_overdue_services' if permission_task_overdue_services?(field_names)
    new_actions << 'cases_by_task_overdue_followups' if field_names.include?('followup_needed_by_date')
    new_actions
  end

  def permission_actions_dashboard_form_dependent(actions, opts = {})
    forms = role_forms(opts[:permitted_form_ids])
    form_ids = forms.values.flatten.map(&:unique_id) if forms && forms.values && forms.values.flatten
    field_names = forms.map do |_, v|
      v.map { |form| form.fields.map { |field| field.name if field.visible? } }
    end

    field_names = field_names.flatten.compact if field_names && field_names.flatten
    new_actions = []
    new_actions += permission_actions_dashboard_overview(form_ids, opts)
    new_actions += permission_actions_dashboard_task_overdue(actions, field_names)
    new_actions
  end

  def permission_actions_dashboard_shared(opts = {})
    new_actions = []
    new_actions << 'dash_shared_with_me' if opts[:view_assessment] || receive_permissions?(opts[:case_permissions])
    new_actions << 'dash_shared_with_others' if share_permissions?(opts[:case_permissions])
    new_actions
  end

  def permission_actions_dashboard_overview(form_ids, opts = {})
    return %w[dash_group_overview] if %w[group all].include?(opts[:group_permission])

    return [] unless opts[:group_permission] == 'self'

    form_ids.include?('incident_details_container') ? %w[dash_case_incident_overview] : %w[case_overview]
  end

  def permission_actions_dashboard_group_all(opts = {})
    return [] unless opts[:group_permission] == 'all'

    %w[dash_reporting_location dash_protection_concerns]
  end

  def permission_workflow?(opts = {})
    return true if opts[:view_response]

    return false unless opts[:group_permission] == 'self'

    opts[:module_unique_ids].any? { |module_id| @module_hash[module_id].use_workflow_service_implemented if @module_hash.key:(module_id) }
  end

  def permission_actions_dashboard(actions, opts = {})
    return [] if actions.blank?

    new_actions = actions - %w[view_approvals view_assessment dash_cases_by_workflow dash_cases_by_task_overdue
                               dash_manager_transfers dash_referrals_by_socal_worker dash_transfers_by_socal_worker
                               view_response manage]
    new_actions << 'case_risk' if actions.include?('view_assessment')
    new_actions << 'workflow_team' if actions.include?('dash_cases_by_workflow')
    new_actions << 'workflow' if permission_workflow?(opts.merge(view_response: actions.include?('view_response')))
    new_actions << 'dash_shared_with_my_team' if actions.include?('dash_referrals_by_socal_worker')
    new_actions << 'dash_shared_from_my_team' if actions.include?('dash_transfers_by_socal_worker')
    new_actions << 'dash_flags' if opts[:case_permissions].present?
    new_actions += permission_actions_dashboard_shared(view_assessment: actions.include?('view_assessment'),
                                                       case_permissions: opts[:case_permissions])
    new_actions += permission_actions_dashboard_group_all(opts)
    new_actions += permission_actions_dashboard_approval(opts) if actions.include?('view_approvals')
    new_actions += permission_actions_dashboard_form_dependent(actions, opts)
    new_actions.uniq
  end

  def default_dashboard_permissions(opts = {})
    new_actions = permission_actions_dashboard_overview([], opts)
    new_actions << 'dash_flags' if opts[:case_permissions].present?
    new_actions += permission_actions_dashboard_shared(view_assessment: false,
                                                       case_permissions: opts[:case_permissions])
    new_actions += permission_actions_dashboard_group_all(opts)
    new_actions << 'workflow' if permission_workflow?(opts.merge(view_response: false))
    new_actions
  end

  def permission_actions(permission, opts = {})
    resources_to_modify = %w[case incident tracing_request dashboard]
    return permission.actions unless resources_to_modify.include?(permission.resource)

    send("permission_actions_#{permission.resource}", permission.actions, opts)
  end

  def case_permissions(permissions)
    result = permissions.select { |p| p.resource == 'case' }
    result.first.actions if result.first
  end

  def add_incident_from_case?(permissions, permission, opts = {})
    return false unless permission.resource == 'case' && permissions.map(&:resource).exclude?('incident')

    return true if opts.key?(:role_form_ids) && opts[:role_form_ids].include?('incident_details_container')
    false
  end

  def incident_permissions_from_case(case_permission)
    new_actions = []
    new_actions << 'read' if case_permission.actions.include?('read')
    new_actions << 'write' if (case_permission.actions & %w[create write]).any?
    new_actions
  end

  def role_reporting_location_level(object)
    return nil if object.reporting_location_level.blank? || system_settings.reporting_location_config.blank?

    system_settings.reporting_location_config.admin_level_map[object.reporting_location_level]
  end

  def role_permissions(permissions, opts = {})
    object_hash = {}
    opts[:role_form_ids] = role_form_ids(opts[:permitted_form_ids])
    json_hash = permissions.inject({}) do |hash, permission|
      opts[:case_permissions] = case_permissions(permissions) if permission.resource == 'dashboard'
      hash[permission.resource] = permission_actions(permission, opts)
      if add_incident_from_case?(permissions, permission, opts)
        hash['incident'] = incident_permissions_from_case(permission)
      end
      object_hash[Permission::AGENCY] = permission.agency_ids if permission.agency_ids.present?
      object_hash[Permission::ROLE] = permission.role_ids if permission.role_ids.present?
      hash
    end
    if json_hash.keys.exclude?('dashboard')
      opts[:case_permissions] = case_permissions(permissions)
      json_hash['dashboard'] = default_dashboard_permissions(opts)
    end
    json_hash['objects'] = object_hash if object_hash.present?
    json_hash
  end

  def configuration_hash_role(object)
    config_hash = object.attributes
                        .except('id', 'permissions_list', 'permitted_form_ids', 'reporting_location_level')
                        .merge(unique_id(object))
                        .with_indifferent_access
    config_hash['is_manager'] = %w[all group].include?(object.group_permission)
    config_hash['module_unique_ids'] = role_module(object)
    config_hash['reporting_location_level'] = role_reporting_location_level(object)
    config_hash['permissions'] = role_permissions(object.permissions_list,
                                                  id: object.id,
                                                  permitted_form_ids: object.permitted_form_ids,
                                                  group_permission: object.group_permission,
                                                  module_unique_ids: config_hash['module_unique_ids'])
    config_hash['form_section_read_write'] = role_permitted_form_hash(object.permitted_form_ids)
    config_hash
  end

  def config_object_names
    %w[Role]
  end
end
