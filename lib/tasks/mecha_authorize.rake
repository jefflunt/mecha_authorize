# frozen_string_literal: true

require "tiny_color"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/inflections"
require_relative "../mecha_authorize"

class String
  def dark_grey
    respond_to?(:grey) ? grey : self
  end unless method_defined?(:dark_grey)

  def dark_gray
    respond_to?(:gray) ? gray : self
  end unless method_defined?(:dark_gray)
end

desc "Print all routes and their MechaAuthorize authorization controls"
task :mecha_authorize, [:role] => :environment do |_t, args|
  role_arg = args[:role]&.to_s&.strip
  matcher = MechaAuthorize.matcher
  colors = MechaAuthorize.configuration.debug_colorization

  if role_arg && !role_arg.empty?
    unless matcher.valid_role?(role_arg)
      valid_roles = (matcher.role_names + matcher.personas.keys).uniq.join(", ")
      puts "ERROR: Role '#{role_arg}' does not exist in config/mecha_authorize.yml (valid roles: #{valid_roles})"
      exit(1)
    end
  end

  routes = Rails.application.routes.routes.map { |r| ActionDispatch::Routing::RouteWrapper.new(r) }.reject(&:internal?)

  all_mapped_routes = []

  routes.each do |r|
    if r.engine?
      engine_routes = r.rack_app.routes
      engine_routes = engine_routes.routes if engine_routes.is_a?(ActionDispatch::Routing::RouteSet)

      clean_mount = r.path.sub("(.:format)", "").sub("/*path", "").sub("/*filename", "").chomp("/")

      engine_routes.map { |er| ActionDispatch::Routing::RouteWrapper.new(er) }.reject(&:internal?).each do |er|
        full_path = "#{clean_mount}#{er.path}".sub("(.:format)", "")
        verb = er.verb.to_s.empty? ? "*" : er.verb.to_s.upcase
        target = if er.respond_to?(:controller) && er.controller.present? && er.action.present?
          "#{er.controller.camelize}Controller##{er.action}"
        end
        all_mapped_routes << { verb: verb, path: full_path, target: target }
      end
    else
      verb = r.verb.to_s.empty? ? "*" : r.verb.to_s.upcase
      target = if r.respond_to?(:controller) && r.controller.present? && r.action.present?
        "#{r.controller.camelize}Controller##{r.action}"
      end
      all_mapped_routes << { verb: verb, path: r.path.sub("(.:format)", ""), target: target }
    end
  end

  if role_arg && !role_arg.empty?
    role_sym = role_arg.to_sym
    users = matcher.resolve_users_for_role(role_sym, MechaAuthorize.configuration.user_resolvers)

    if users.empty?
      puts "NO USERS FOUND IN ROLE '#{role_arg}'"
    else
      puts "Users in role '#{role_arg}' (#{users.size} found):"
      users.each do |u|
        puts "  - #{matcher.format_user_entry(u)}"
      end
    end

    puts "\nRoutes authorized for '#{role_arg}':"
    authorized_routes = all_mapped_routes.select do |r|
      rule = matcher.match_route_spec(r[:verb], r[:path])
      rule && rule[role_sym] == true
    end

    max_verb_len = [authorized_routes.map { |r| r[:verb].to_s.length }.max || 4, 4].max
    max_path_len = [authorized_routes.map { |r| r[:path].to_s.length }.max || 11, 11].max

    authorized_routes.each do |r|
      if r[:target]
        puts sprintf("  %-#{max_verb_len}s  %-#{max_path_len}s  => %s", r[:verb], r[:path], r[:target])
      else
        puts sprintf("  %-#{max_verb_len}s  %s", r[:verb], r[:path])
      end
    end
    next
  end

  colorize_char = ->(char, perm) {
    return char if char == "." && perm != :none
    color = colors[perm]
    if color && char.respond_to?(color)
      char.send(color)
    else
      char
    end
  }

  max_verb_len = all_mapped_routes.map { |r| r[:verb].to_s.length }.max || 4
  max_verb_len = [max_verb_len, 4].max

  max_path_len = all_mapped_routes.map { |r| r[:path].to_s.length }.max || 11
  max_path_len = [max_path_len, 11].max

  puts sprintf("%-#{max_verb_len}s %-#{max_path_len}s %s", "Verb", "URI Pattern", "Access")

  all_mapped_routes.each do |r|
    rule = matcher.match_route_spec(r[:verb], r[:path])

    has_access = rule && (rule[:public] || rule[:admin] || rule[:user_ui] || rule[:user_api])

    if has_access
      public_char  = rule[:public] ? "P" : "."
      admin_char   = rule[:admin] ? "A" : "."
      user_ui_char = rule[:user_ui] ? "U" : "."
      user_api_char = rule[:user_api] ? "X" : "."

      color_to_apply = if rule[:public]
        colors[:public]
      elsif rule[:admin]
        colors[:admin]
      elsif rule[:user_ui]
        colors[:user_ui]
      elsif rule[:user_api]
        colors[:user_api]
      end

      public_colorized   = colorize_char.call(public_char, :public)
      admin_colorized    = colorize_char.call(admin_char, :admin)
      user_ui_colorized  = colorize_char.call(user_ui_char, :user_ui)
      user_api_colorized = colorize_char.call(user_api_char, :user_api)
    else
      public_char  = "."
      admin_char   = "."
      user_ui_char = "."
      user_api_char = "."

      color_to_apply = colors[:none]

      public_colorized   = colorize_char.call(public_char, :none)
      admin_colorized    = colorize_char.call(admin_char, :none)
      user_ui_colorized  = colorize_char.call(user_ui_char, :none)
      user_api_colorized = colorize_char.call(user_api_char, :none)
    end

    padded_path = sprintf("%-#{max_path_len}s", r[:path])
    path_colorized = if color_to_apply && padded_path.respond_to?(color_to_apply)
      padded_path.send(color_to_apply)
    else
      padded_path
    end

    access_string = "#{public_colorized}#{admin_colorized}#{user_ui_colorized}#{user_api_colorized}"
    puts sprintf("%-#{max_verb_len}s %s %s", r[:verb], path_colorized, access_string)
  end
end

namespace :mecha_authorize do
  namespace :verify do
    desc "Statically verify route authorization parity, dead rules, and engine protection"
    task static: :environment do
      puts "Running MechaAuthorize static route audit..."
      auditor = MechaAuthorize::Auditor::Static.new
      result = auditor.audit

      puts "  -> #{result.mapped_routes.size} routes mapped to explicit authorization rules"

      if result.unmapped_routes.any?
        puts "  -> #{result.unmapped_routes.size} unmapped routes (defaulting to closed-by-default 404):"
        result.unmapped_routes.each do |r|
          puts "     [404] #{r[:verb]} #{r[:path]}"
        end
      end

      if result.dead_rules.any?
        puts "\nERROR: Found #{result.dead_rules.size} dead/stale rule(s) in mecha_authorize.yml:".light_red
        result.dead_rules.each do |dr|
          puts "  - #{dr[:verb]} #{dr[:pattern]}"
        end
      end

      if result.engine_warnings.any?
        puts "\nWARNING: Mounted engine bypass warning(s):".light_red
        result.engine_warnings.each do |w|
          puts "  - #{w}"
        end
      end

      if result.success?
        puts "\n✓ Static route authorization audit passed: 0 dead rules, 0 engine bypasses.".green
      else
        abort("\n✗ Static route authorization audit failed. Please prune dead rules or resolve engine bypasses.")
      end
    end

    desc "Run behavioral persona matrix test suite"
    task behavioral: :environment do
      puts "Running MechaAuthorize behavioral persona matrix test suite..."
      matrix_test_path = File.expand_path("../mecha_authorize/matrix_test.rb", __dir__)
      system({ "MECHA_MATRIX_STANDALONE" => "1" }, "bin/rails", "test", matrix_test_path) || abort("Behavioral verification failed.")
    end
  end

  desc "Run both static parity and behavioral persona verification"
  task verify: %w[verify:static verify:behavioral]
end
