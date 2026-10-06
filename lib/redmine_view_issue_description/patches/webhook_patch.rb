# frozen_string_literal: true

module RedmineViewIssueDescription
  module Patches
    # Redmine 7 webhooks send the core issue API payload (show.api.rsb, with the
    # description and the journal) to every hook whose owner can see the issue.
    # This plugin refuses that same content on the issue page and in the API
    # show to users without detail access, so an issue event is only delivered
    # to hooks whose owner may open the issue.
    module WebhookPatch
      def hooks_for(event, object)
        hooks = super
        return hooks unless object.is_a?(Issue)

        hooks.select { |hook| object.detail_access_granted?(hook.user) }
      end
    end
  end
end

# Webhooks exist from Redmine 7 on.
if defined?(Webhook) && !Webhook.singleton_class.ancestors.include?(RedmineViewIssueDescription::Patches::WebhookPatch)
  Webhook.singleton_class.prepend(RedmineViewIssueDescription::Patches::WebhookPatch)
end
