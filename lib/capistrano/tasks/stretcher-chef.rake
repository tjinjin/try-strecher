# -*- coding: utf-8; mode: ruby -*-
require 'erb'
require 'yaml'

namespace :stretcher do
  set :exclude_dirs, ['tmp']

  def local_working_path_base
    @_local_working_path_base ||= fetch(:local_working_path_base, "/var/tmp/#{fetch :application}")
  end

  def local_repo_path
    "#{local_working_path_base}/repo"
  end

  def local_checkout_path
    "#{local_working_path_base}/checkout"
  end

  def local_build_path
    "#{local_working_path_base}/build"
  end

  def local_tarball_path
    "#{local_working_path_base}/tarballs"
  end

  def application_builder_roles
    roles(fetch(:application_builder_roles, [:build]))
  end

  task :mark_deploying do
    set :deploying, true
  end

  desc "Create a tarball that is set up for deploy"
  task :archive_project =>
    [:ensure_directories, :checkout_local,
     :create_tarball, :upload_tarball,
     :create_and_upload_manifest, :cleanup_dirs]

  task :ensure_directories do
    on application_builder_roles do
      execute :mkdir, '-p', local_repo_path, local_checkout_path, local_build_path, local_tarball_path
    end
  end

  task :checkout_local do
    on application_builder_roles do
      if test("[ -f #{local_repo_path}/HEAD ]")
        within local_repo_path do
          execute :git, :remote, :update
        end
      else
        execute :git, :clone, '--mirror', repo_url, local_repo_path
      end

      within local_repo_path do
        execute :mkdir, '-p', "#{local_checkout_path}/#{env.now}"
        execute :git, :archive, fetch(:branch), "| tar -x -C", "#{local_checkout_path}/#{env.now}"
        set :current_revision, capture(:git, 'rev-parse', fetch(:branch)).chomp

        execute :echo, fetch(:current_revision), "> #{local_checkout_path}/#{env.now}/REVISION"

        execute :rsync, "-av", "--delete",
          *fetch(:exclude_dirs).map{|d| ['--exclude', d].join(' ')},
          "#{local_checkout_path}/#{env.now}/", "#{local_build_path}/",
          "| pv -l -s $( find #{local_checkout_path}/#{env.now}/ -type f | wc -l ) >/dev/null"
      end
    end
  end

  task :create_tarball do
    on application_builder_roles do
      within local_build_path do
        execute :mkdir, '-p', "#{local_tarball_path}/#{env.now}"
        execute :tar, '-cf', '-',
          "--exclude aws", "--exclude spec", "./",
          "--exclude terraform",
          "| pv -s $( du -sb ./ | awk '{print $1}' )",
          "| gzip -9 > #{local_tarball_path}/#{env.now}/#{fetch(:local_tarball_name)}"
      end
      within local_tarball_path do
        execute :rm, '-f', 'current'
        execute :ln, '-sf', env.now, 'current'
      end
    end
  end

  task :upload_tarball do
    on application_builder_roles do
      as 'root' do
        execute :aws, :s3, :cp, "#{local_tarball_path}/current/#{fetch(:local_tarball_name)}", fetch(:stretcher_src)
      end
    end
  end

  task :create_and_upload_manifest do
    on application_builder_roles do
      as 'root' do
        failure_message = "Deploy failed at *$(hostname)* :fire:"
        checksum = capture("openssl sha256 #{local_tarball_path}/current/#{fetch(:local_tarball_name)} | gawk -F' ' '{print $2}'").chomp
        src = fetch(:stretcher_src)
        template = File.read(File.expand_path('../../templates/manifest.yml.erb', __FILE__))
        yaml = YAML.load(ERB.new(capture(:cat, "#{local_build_path}/#{fetch(:stretcher_hooks)}")).result(binding))
        fetch(:deploy_roles).split(',').each do |role|
          hooks = yaml[role]
          yml = ERB.new(template).result(binding)
          tempfile_path = Tempfile.open("manifest_#{role}") do |t|
            t.write yml
            t.path
          end
          upload! tempfile_path, "#{local_tarball_path}/current/manifest_#{role}_#{fetch(:stage)}.yml"
          execute :aws, :s3, :cp, "#{local_tarball_path}/current/manifest_#{role}_#{fetch(:stage)}.yml", "#{fetch(:manifest_path)}/manifest_#{role}_#{fetch(:stage)}.yml"
        end
      end
    end
  end

  # refs https://github.com/capistrano/capistrano/blob/master/lib/capistrano/tasks/deploy.rake#L138
  task :cleanup_dirs do
    on application_builder_roles do
      releases = capture(:ls, '-tr', "#{local_tarball_path}", "| grep -v current").split

      if releases.count >= fetch(:keep_releases)
        info t(:keeping_releases, host: host.to_s, keep_releases: fetch(:keep_releases), releases: releases.count)
        directories = (releases - releases.last(fetch(:keep_releases)))
        unless directories.empty?
          directories_str = directories.map do |release|
            "#{local_tarball_path}/#{release} #{local_checkout_path}/#{release}"
          end.join(" ")
          execute :rm, '-rf', directories_str
        else
          info t(:no_old_releases, host: host.to_s, keep_releases: fetch(:keep_releases))
        end
      end
    end
  end

  desc "Kick the stretcher's deploy event via Consul"
  task :kick_stretcher do
    fetch(:deploy_roles).split(',').each do |target_role|
      on application_builder_roles do
        opts = ["-name deploy_#{target_role}_#{fetch(:stage)}"]
        opts << "-node #{ENV['TARGET_HOSTS']}" if ENV['TARGET_HOSTS']
        opts << "#{fetch(:manifest_path)}/manifest_#{target_role}_#{fetch(:stage)}.yml"
        execute :consul, :event, *opts
      end
    end
  end

  desc 'Deploy via Stretcher'
  task :deploy => ["stretcher:mark_deploying", "stretcher:archive_project", "stretcher:kick_stretcher"]
end

