module JIRA::RemoteAPI

  # @group Issues

  ##
  # @note During my own testing, I found that HTTP requests could timeout
  #       for really large requests (~2500 results) if you are not on the
  #       same network. So I set a more reasonable upper limit; feel free
  #       to override it, but be aware of the potential issues.
  #
  # This method is the equivalent of making an advanced search from the web
  # interface.
  #
  # The {JIRA::Issue} structure does not include any comments or attachments.
  #
  # @param [String] jql_query JQL query as a string
  # @param [Fixnum] max_results limit on number of returned results;
  #   the value may be overridden by the server if max_results is too large
  # @return [Array<JIRA::Issue>]
  def issues_from_jql_search jql_query, max_results = 2000
    array_jira_call JIRA::Issue, 'getIssuesFromJqlSearch', jql_query, max_results
  end

  ##
  # This method can update most, but not all, issue fields. Some limitations
  # are because of how the API is designed, and some are because I have not
  # yet implemented the ability to update fields made of custom objects
  # (things in the JIRA module).
  #
  # Fields known to not update via this method:
  #
  #  - status - use {#progress_workflow_action}
  #  - attachments - use {#add_base64_encoded_attachments_to_issue_with_key}
  #
  # Though {JIRA::FieldValue} objects have an id field, they do not expect
  # to be given id values. You must use the camel cased name of the field you
  # wish to update, such as `'fixVersions'` to update the `fix_versions` for
  # an issue.
  #
  # However, there is at least one exception to the rule; when you wish to
  # update the affected versions for an issue, you should use `'versions'`
  # instead of `'affectsVersions'`. You need to be careful about these
  # cases as it has been reported that JIRA will silently fail to update
  # fields it does not know about.
  #
  # Updating nested fields can be tricky, see the example on cascading
  # select field's to see how it would be done.
  #
  # A final note, some fields only should be passed the id in order to
  # update them, as shown in the version updating example.
  #
  # @example Usage With A Normal Field
  #
  #   summary      = JIRA::FieldValue.new 'summary', 'My new summary'
  #
  # @example Usage With A Custom Field
  #
  #   custom_field = JIRA::FieldValue.new 'customfield_10060', '123456'
  #
  # @example Setting a field to be blank/nil
  #
  #   description  = JIRA::FieldValue.new 'description'
  #
  # @example Calling the method to update an issue
  #
  #   jira.update_issue 'PROJECT-1', description, custom_field
  #
  # @example Setting the value of a cascading select field
  #
  #   part1 = JIRA::FieldValue.new 'customfield_10285',   'Main Detail'
  #   part2 = JIRA::FieldValue.new 'customfield_10285:1', 'First Subdetail'
  #   jira.update_issue 'PROJECT-1', part1, part2
  #
  # @example Changing the affected versions for an issue
  #
  #   version = jira.versions_for_project.find { |x| x.name = 'v1.0beta' }
  #   field   = JIRA::FieldValue.new 'versions', version.id
  #   jira.update_issue 'PROJECT-1', field
  #
  # @param [String] issue_key
  # @param [JIRA::FieldValue] *field_values
  # @return [JIRA::Issue]
  def update_issue issue_key, *field_values
    JIRA::Issue.new_with_xml jira_call('updateIssue', issue_key, field_values)
  end

  ##
  # Some fields will be ignored when an issue is created.
  #
  #  - reporter - you cannot override this value at creation
  #  - resolution
  #  - attachments
  #  - votes
  #  - status
  #  - due date - I think this is a bug in jiraSOAP or JIRA
  #  - environment - I think this is a bug in jiraSOAP or JIRA
  #
  # @param [JIRA::Issue] issue
  # @return [JIRA::Issue]
  def create_issue_with_issue issue
    JIRA::Issue.new_with_xml jira_call( 'createIssue', issue )
  end

  # @param [JIRA::Issue] issue
  # @param [String] parent_id
  # @return [JIRA:Issue]
  def create_issue_with_issue_and_parent issue, parent_id
    JIRA::Issue.new_with_xml jira_call('createIssueWithParent', issue, parent_id)
  end
  alias_method :create_issue_with_parent, :create_issue_with_issue_and_parent

  # @param [String] issue_key
  # @return [JIRA::Issue]
  def issue_with_key issue_key
    JIRA::Issue.new_with_xml jira_call( 'getIssue', issue_key )
  end

  # @param [String] issue_id
  # @return [JIRA::Issue]
  def issue_with_id issue_id
    JIRA::Issue.new_with_xml jira_call( 'getIssueById', issue_id )
  end

  # @param [String] id
  # @param [Fixnum] max_results
  # @param [Fixnum] offset
  # @return [Array<JIRA::Issue>]
  def issues_from_filter_with_id id, max_results = 500, offset = 0
    array_jira_call JIRA::Issue, 'getIssuesFromFilterWithLimit', id, offset, max_results
  end

  # @param [String] issue_id
  # @return [Time]
  def resolution_date_for_issue_with_id issue_id
    jira_call( 'getResolutionDateById', issue_id ).to_iso_date
  end

  # @param [String] issue_key
  # @return [Time]
  def resolution_date_for_issue_with_key issue_key
    jira_call( 'getResolutionDateByKey', issue_key ).to_iso_date
  end

  ##
  # This method acts like {#update_issue} except that it also updates
  # the status of the issue.
  #
  # The `action_id` parameter comes from the `id` of an available action.
  # Normally you will use this method in conjunction with
  # {#available_actions} to decide which action to take.
  #
  # @param [String] issue_key
  # @param [String] action_id this is the id of workflow action
  # @param [JIRA::FieldValue] *field_values
  # @return [JIRA::Issue]
  def progress_workflow_action issue_key, action_id, *field_values
    JIRA::Issue.new_with_xml jira_call('progressWorkflowAction',
                                       issue_key, action_id, field_values)
  end

  ##
  # Returns workflow actions available for an issue.
  #
  # @param [String] issue_key
  # @return [Array<JIRA::NamedEntity>]
  def available_actions issue_key
    array_jira_call JIRA::NamedEntity, 'getAvailableActions', issue_key
  end

end
