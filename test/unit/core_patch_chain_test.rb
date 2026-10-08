# frozen_string_literal: true

require_relative '../test_helper'

# Jan's general decision of 2026-10-07: core methods are patched with prepend,
# never with an alias_method chain (mixing both on one method recurses). This
# test fails as soon as one of the plugin's chains is an alias again, and shows
# that another plugin may stack a prepend or an alias on top without recursion.
class CorePatchChainTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :issue_statuses, :enumerations, :issues

  CHAINS = [
    [Issue, :visible?, :visible_without_vid?],
    [Issue, :valid_watcher?, :valid_watcher_without_vid?],
    [Issue.singleton_class, :visible_condition, :visible_condition_without_vid],
    [Query, :columns, :columns_without_ifv],
    [Query, :available_block_columns, :available_block_columns_without_ifv],
    [Query, :has_column?, :has_column_without_ifv?],
    [ActivitiesController, :index, :index_without_vid],
    [WatchersController, :users_for_new_watcher, :users_for_new_watcher_without_vid]
  ].freeze

  PLUGIN_DIR = File.expand_path('../..', __dir__)

  CHAINS.each do |klass, name, without|
    label = klass.singleton_class? ? "Issue.#{name}" : "#{klass}##{name}"
    test "#{label} is prepended, core's method is untouched" do
      assert_not_equal klass, klass.instance_method(without).owner,
                       "#{without} is defined on #{klass} itself: an alias_method chain"

      ours = klass.instance_method(name)
      ours = ours.super_method while ours && !(ours.owner.name.to_s.start_with?('RedmineViewIssueDescription::PrependChain::'))
      assert ours, "#{label} is not wrapped by a PrependChain module"

      core = ours.super_method
      assert core, "nothing below the plugin's #{label}"
      assert_not core.source_location.first.start_with?(PLUGIN_DIR),
                 "below the prepend #{label} comes from the plugin again: #{core.source_location.first}"
    end
  end

  test 'a later prepend on Issue#visible? from another plugin does not recurse' do
    other = Module.new { def visible?(usr = nil) = super }
    klass = Class.new(Issue) { prepend other }

    assert klass.find(1).visible?(User.find(1))
  end

  test 'a later alias_method chain on Issue#visible? from another plugin does not recurse' do
    klass = Class.new(Issue) do
      alias_method :visible_without_other?, :visible?
      def visible?(usr = nil) = visible_without_other?(usr)
    end

    assert klass.find(1).visible?(User.find(1))
  end
end
