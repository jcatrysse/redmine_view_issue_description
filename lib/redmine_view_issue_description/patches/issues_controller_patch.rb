# frozen_string_literal: true

module RedmineViewIssueDescription
  module Patches
    module IssuesControllerPatch
      module InstanceMethods
        def show_with_vid
          unless vid_description_access?
            render_403
            return
          end

          show_without_vid
        end

        def edit_with_vid
          unless vid_description_access?
            render_403
            return
          end

          edit_without_vid
        end

        def update_with_vid
          unless vid_description_access?
            render_403
            return
          end

          update_without_vid
        end

        private

        # Returns true when the current user may access the issue description/detail page.
        # Paths to access:
        #   1. Global admin
        #   2. Assignee of the issue (intentional UX bypass — assignees must be able to work)
        #   3. Watcher with view_watched_issues permission (tracker-scoped)
        #   4. Explicit view_issue_description grant (tracker-scoped, respects issues_visibility)
        def vid_description_access?
          user = User.current
          user.admin? ||
            (!@issue.assigned_to.nil? && user.is_or_belongs_to?(@issue.assigned_to)) ||
            @issue.watcher_access_granted?(user) ||
            @issue.description_access_granted?(user)
        end

        # ── Custom API section injection ─────────────────────────────────────
        # Injects changesets_new and helpdesk_ticket sections into the API
        # response rendered by Redmine core.  This avoids maintaining a full
        # copy of the core issues/show.api.rsb template.

        def inject_vid_api_sections
          return unless api_request? && response.successful?
          return unless @issue

          has_changesets_new   = vid_include_param?('changesets_new')
          has_journal_messages = vid_include_param?('journal_messages')
          return unless has_changesets_new || has_journal_messages

          content_type = response.content_type.to_s
          if content_type.include?('json')
            vid_inject_json(has_changesets_new, has_journal_messages)
          elsif content_type.include?('xml')
            vid_inject_xml(has_changesets_new, has_journal_messages)
          end
        rescue StandardError => e
          logger.warn("[redmine_view_issue_description] Failed to inject API sections: #{e.message}")
        end

        def vid_include_param?(key)
          includes = params[:include]
          if includes.is_a?(Array)
            includes.map(&:to_s).include?(key)
          else
            includes.to_s.split(',').map(&:strip).include?(key)
          end
        end

        def include_changesets_new?
          vid_include_param?('changesets_new')
        end

        def include_journal_messages?
          vid_include_param?('journal_messages')
        end

        # ── Helpdesk access (S1) ─────────────────────────────────────────────
        # Requires BOTH view_helpdesk_tickets AND view_issue_description.
        # Admin bypasses all checks.

        def vid_helpdesk_access?
          return false unless @issue.respond_to?(:helpdesk_ticket) && @issue.helpdesk_ticket
          return true if User.current.admin?

          User.current.allowed_to?(:view_helpdesk_tickets, @issue.project) &&
            @issue.description_access_granted?(User.current)
        end

        # ── JSON injection ───────────────────────────────────────────────────

        def vid_inject_json(has_changesets_new, has_journal_messages)
          data = JSON.parse(response.body)
          issue_data = data['issue']
          return unless issue_data

          issue_data['changesets_new'] = vid_changesets_new_list if has_changesets_new
          issue_data['helpdesk_ticket'] = vid_helpdesk_hash if has_journal_messages && vid_helpdesk_access?

          response.body = data.to_json
        end

        def vid_changesets_new_list
          @issue.changesets.visible.map do |cs|
            entry = {
              'revision' => cs.revision,
              'comments' => cs.comments,
              'committed_on' => cs.committed_on
            }
            entry['user'] = { 'id' => cs.user_id, 'name' => cs.user.name } if cs.user
            if cs.repository
              entry['repository'] = {
                'id' => cs.repository.id,
                'identifier' => cs.repository.identifier.to_s,
                'name' => cs.repository.name.to_s
              }
            end
            entry
          end
        end

        def vid_helpdesk_hash
          ticket = @issue.helpdesk_ticket
          data = {
            'id' => ticket.issue.id,
            'from_address' => ticket.from_address,
            'to_address' => ticket.to_address || '',
            'cc_address' => ticket.cc_address,
            'message_id' => ticket.message_id,
            'ticket_date' => vid_format_date(ticket.ticket_date),
            'content' => ticket.issue.description,
            'source' => ticket.ticket_source_name,
            'is_incoming' => ticket.is_incoming,
            'reaction_time' => ticket.reaction_time || '',
            'first_response_time' => ticket.first_response_time || '',
            'resolve_time' => ticket.resolve_time || '',
            'last_agent_response_at' => vid_format_date(ticket.last_agent_response_at) || '',
            'last_customer_response_at' => vid_format_date(ticket.last_customer_response_at) || '',
            'vote' => ticket.vote,
            'vote_comment' => ticket.vote_comment
          }

          if ticket.customer.present?
            data['contact'] = { 'id' => ticket.contact_id, 'name' => ticket.customer.name }
          end

          if ticket.message_file.present?
            data['message_file'] = vid_attachment_hash(ticket.message_file)
          end

          if vid_include_param?('journal_messages')
            data['journal_messages'] = ticket.issue.journal_messages.map { |jm| vid_journal_message_hash(jm) }
          end

          if vid_include_param?('journals')
            data['journals'] = ticket.journals.map do |j|
              { 'id' => j.id, 'notes' => j.notes, 'created_on' => j.created_on }
            end
          end

          data
        end

        def vid_journal_message_hash(jm)
          entry = {
            'from_address' => jm.from_address,
            'to_address' => jm.to_address,
            'cc_address' => jm.cc_address,
            'bcc_address' => jm.bcc_address,
            'message_date' => vid_format_date(jm.message_date),
            'is_incoming' => jm.is_incoming,
            'content' => jm.content,
            'message_id' => jm.message_id,
            'journal_id' => jm.journal_id,
            'viewed_on' => jm.viewed_on
          }
          if jm.contact.present?
            entry['contact'] = { 'id' => jm.contact_id, 'name' => jm.contact.name }
          end
          if jm.message_file.present?
            entry['message_file'] = vid_attachment_hash(jm.message_file)
          end
          entry
        end

        def vid_attachment_hash(attachment)
          data = {
            'id' => attachment.id,
            'filename' => attachment.filename,
            'filesize' => attachment.filesize,
            'content_type' => attachment.content_type,
            'description' => attachment.description,
            'created_on' => attachment.created_on
          }
          if attachment.respond_to?(:author) && attachment.author
            data['author'] = { 'id' => attachment.author.id, 'name' => attachment.author.name }
          end
          data
        end

        def vid_format_date(date)
          return nil unless date

          respond_to?(:format_date, true) ? format_date(date) : date.to_s
        end

        # ── XML injection ────────────────────────────────────────────────────

        def vid_inject_xml(has_changesets_new, has_journal_messages)
          require 'nokogiri'
          doc = Nokogiri::XML(response.body)
          issue_node = doc.at_xpath('/issue')
          return unless issue_node

          vid_add_changesets_new_xml(issue_node, doc) if has_changesets_new
          vid_add_helpdesk_xml(issue_node, doc) if has_journal_messages && vid_helpdesk_access?

          response.body = doc.to_xml
        end

        def vid_add_changesets_new_xml(parent, doc)
          array_node = vid_xml_node(doc, 'changesets_new', 'type' => 'array')
          @issue.changesets.visible.each do |cs|
            cs_node = vid_xml_node(doc, 'changeset', 'revision' => cs.revision.to_s)
            cs_node.add_child(vid_xml_attrs(doc, 'user', 'id' => cs.user_id.to_s, 'name' => cs.user.name)) if cs.user
            cs_node.add_child(vid_xml_text(doc, 'comments', cs.comments))
            cs_node.add_child(vid_xml_text(doc, 'committed_on', cs.committed_on))
            if cs.repository
              cs_node.add_child(vid_xml_attrs(doc, 'repository',
                'id' => cs.repository.id.to_s,
                'identifier' => cs.repository.identifier.to_s,
                'name' => cs.repository.name.to_s
              ))
            end
            array_node.add_child(cs_node)
          end
          parent.add_child(array_node)
        end

        def vid_add_helpdesk_xml(parent, doc)
          ticket = @issue.helpdesk_ticket
          ht = vid_xml_node(doc, 'helpdesk_ticket')
          ht.add_child(vid_xml_text(doc, 'id', ticket.issue.id))
          ht.add_child(vid_xml_text(doc, 'from_address', ticket.from_address))
          ht.add_child(vid_xml_text(doc, 'to_address', ticket.to_address || ''))
          ht.add_child(vid_xml_text(doc, 'cc_address', ticket.cc_address))
          ht.add_child(vid_xml_text(doc, 'message_id', ticket.message_id))
          ht.add_child(vid_xml_text(doc, 'ticket_date', vid_format_date(ticket.ticket_date)))
          ht.add_child(vid_xml_text(doc, 'content', ticket.issue.description))
          ht.add_child(vid_xml_text(doc, 'source', ticket.ticket_source_name))
          ht.add_child(vid_xml_text(doc, 'is_incoming', ticket.is_incoming))
          ht.add_child(vid_xml_text(doc, 'reaction_time', ticket.reaction_time || ''))
          ht.add_child(vid_xml_text(doc, 'first_response_time', ticket.first_response_time || ''))
          ht.add_child(vid_xml_text(doc, 'resolve_time', ticket.resolve_time || ''))
          ht.add_child(vid_xml_text(doc, 'last_agent_response_at', vid_format_date(ticket.last_agent_response_at) || ''))
          ht.add_child(vid_xml_text(doc, 'last_customer_response_at', vid_format_date(ticket.last_customer_response_at) || ''))

          if ticket.customer.present?
            ht.add_child(vid_xml_attrs(doc, 'contact', 'id' => ticket.contact_id.to_s, 'name' => ticket.customer.name))
          end

          ht.add_child(vid_xml_text(doc, 'vote', ticket.vote))
          ht.add_child(vid_xml_text(doc, 'vote_comment', ticket.vote_comment))

          if ticket.message_file.present?
            ht.add_child(vid_attachment_xml(doc, 'message_file', ticket.message_file))
          end

          if vid_include_param?('journal_messages')
            jm_array = vid_xml_node(doc, 'journal_messages', 'type' => 'array')
            ticket.issue.journal_messages.each do |jm|
              jm_array.add_child(vid_journal_message_xml(doc, jm))
            end
            ht.add_child(jm_array)
          end

          if vid_include_param?('journals')
            j_array = vid_xml_node(doc, 'journals', 'type' => 'array')
            ticket.journals.each do |j|
              j_node = vid_xml_node(doc, 'journal')
              j_node.add_child(vid_xml_text(doc, 'id', j.id))
              j_node.add_child(vid_xml_text(doc, 'notes', j.notes))
              j_node.add_child(vid_xml_text(doc, 'created_on', j.created_on))
              j_array.add_child(j_node)
            end
            ht.add_child(j_array)
          end

          parent.add_child(ht)
        end

        def vid_journal_message_xml(doc, jm)
          node = vid_xml_node(doc, 'journal_message')
          if jm.contact.present?
            node.add_child(vid_xml_attrs(doc, 'contact', 'id' => jm.contact_id.to_s, 'name' => jm.contact.name))
          end
          node.add_child(vid_xml_text(doc, 'from_address', jm.from_address))
          node.add_child(vid_xml_text(doc, 'to_address', jm.to_address))
          node.add_child(vid_xml_text(doc, 'cc_address', jm.cc_address))
          node.add_child(vid_xml_text(doc, 'bcc_address', jm.bcc_address))
          node.add_child(vid_xml_text(doc, 'message_date', vid_format_date(jm.message_date)))
          node.add_child(vid_xml_text(doc, 'is_incoming', jm.is_incoming))
          node.add_child(vid_xml_text(doc, 'content', jm.content))
          node.add_child(vid_xml_text(doc, 'message_id', jm.message_id))
          node.add_child(vid_xml_text(doc, 'journal_id', jm.journal_id))
          node.add_child(vid_xml_text(doc, 'viewed_on', jm.viewed_on))
          if jm.message_file.present?
            node.add_child(vid_attachment_xml(doc, 'message_file', jm.message_file))
          end
          node
        end

        def vid_attachment_xml(doc, element_name, attachment)
          mf = vid_xml_node(doc, element_name)
          mf.add_child(vid_xml_text(doc, 'id', attachment.id))
          mf.add_child(vid_xml_text(doc, 'filename', attachment.filename))
          mf.add_child(vid_xml_text(doc, 'filesize', attachment.filesize))
          mf.add_child(vid_xml_text(doc, 'content_type', attachment.content_type))
          mf.add_child(vid_xml_text(doc, 'description', attachment.description))
          if attachment.respond_to?(:author) && attachment.author
            mf.add_child(vid_xml_attrs(doc, 'author', 'id' => attachment.author.id.to_s, 'name' => attachment.author.name))
          end
          mf.add_child(vid_xml_text(doc, 'created_on', attachment.created_on))
          mf
        end

        # XML builder helpers

        def vid_xml_node(doc, name, attrs = {})
          node = Nokogiri::XML::Node.new(name, doc)
          attrs.each { |k, v| node[k] = v.to_s }
          node
        end

        def vid_xml_attrs(doc, name, attrs = {})
          vid_xml_node(doc, name, attrs)
        end

        def vid_xml_text(doc, name, value)
          node = Nokogiri::XML::Node.new(name, doc)
          node.content = value.to_s unless value.nil?
          node
        end
      end
    end
  end
end

IssuesController.include(RedmineViewIssueDescription::Patches::IssuesControllerPatch::InstanceMethods)
IssuesController.class_eval do
  unless method_defined?(:show_without_vid)
    alias_method :show_without_vid, :show
    alias_method :show, :show_with_vid
  end
  unless method_defined?(:edit_without_vid)
    alias_method :edit_without_vid, :edit
    alias_method :edit, :edit_with_vid
  end
  unless method_defined?(:update_without_vid)
    alias_method :update_without_vid, :update
    alias_method :update, :update_with_vid
  end

  after_action :inject_vid_api_sections, only: [:show]
end
