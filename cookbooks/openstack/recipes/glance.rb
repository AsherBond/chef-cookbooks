#
# Cookbook Name:: memcache
# Recipe:: default
#
# Copyright 2009, Example Com
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "openstack::apt"
include_recipe "openstack::mysql"
include_recipe "openstack::keystone"

package "curl" do
  action :install
end

package "python-mysqldb" do
  action :install
end

package "glance" do
  action :upgrade
end

service "glance-api" do
  supports :status => true, :restart => true
  action :enable
end

service "glance-registry" do
  supports :status => true, :restart => true
  action :enable
end

execute "glance-manage db_sync" do
        command "glance-manage db_sync"
        action :nothing
        notifies :restart, resources(:service => "glance-registry"), :immediately
end

file "/var/lib/glance/glance.sqlite" do
    action :delete
end

directory "/etc/glance" do
  owner "glance"
  group "glance"
  mode "0750"
end

template "/etc/glance/glance-registry.conf" do
  source "glance-registry.conf.erb"
  owner "glance"
  group "glance"
  mode "0640"
  variables(
    :registry_port => node[:glance][:registry_port],
    :user => node[:glance][:db_user],
    :passwd => node[:glance][:db_passwd],
    :ip_address => node[:controller_ipaddress],
    :db_name => node[:glance][:db],
    :service_port => node[:keystone][:service_port],
    :admin_port => node[:keystone][:admin_port],
    :admin_token => node[:keystone][:admin_token]
  )
  notifies :run, resources(:execute => "glance-manage db_sync"), :immediately
end

template "/etc/glance/glance-api.conf" do
  source "glance-api.conf.erb"
  owner "glance"
  group "glance"
  mode "0640"
  variables(
    :api_port => node[:glance][:api_port],
    :registry_port => node[:glance][:registry_port],
    :ip_address => node[:controller_ipaddress],
    :service_port => node[:keystone][:service_port],
    :admin_port => node[:keystone][:admin_port],
    :admin_token => node[:keystone][:admin_token]
  )
  notifies :restart, resources(:service => "glance-api"), :immediately
end

template "/etc/glance/glance-scrubber.conf" do
  source "glance-scrubber.conf.erb"
  owner "glance"
  group "glance"
  mode "0640"
  variables(
    :user => node[:glance][:db_user],
    :passwd => node[:glance][:db_passwd],
    :ip_address => node[:controller_ipaddress],
    :db_name => node[:glance][:db]
  )
end

template "/etc/glance/glance-api-paste.ini" do
  source "glance-api-paste.ini.erb"
  owner "glance"
  group "glance"
  mode "0640"
  variables(
    :ip_address => node[:controller_ipaddress],
    :service_port => node[:keystone][:service_port],
    :admin_port => node[:keystone][:admin_port],
    :admin_token => node[:keystone][:admin_token]
  )
  notifies :restart, resources(:service => "glance-api"), :immediately
end

template "/etc/glance/glance-registry-paste.ini" do
  source "glance-registry-paste.ini.erb"
  owner "glance"
  group "glance"
  mode "0640"
  variables(
    :ip_address => node[:controller_ipaddress],
    :service_port => node[:keystone][:service_port],
    :admin_port => node[:keystone][:admin_port],
    :admin_token => node[:keystone][:admin_token]
  )
  notifies :restart, resources(:service => "glance-registry"), :immediately
end

template "/etc/glance/policy.json" do
  source "glance-api-policy.json.erb"
  owner "glance"
  group "glance"
  mode "0640"
  notifies :restart, resources(:service => "glance-api"), :immediately
end

node[:glance][:images].each do |img|
  bash "default image setup for #{img.to_s}" do
    cwd "/tmp"
    user "root"
    code <<-EOH
      set -e
      set -x
      mkdir -p images

      curl #{node[:image][img.to_sym]} | tar -zx -C images/
      image_name=$(basename #{node[:image][img]} .tar.gz)

      image_name=${image_name%-multinic}

      kernel_file=$(ls images/*vmlinuz-virtual | head -n1)
      if [ ${#kernel_file} -eq 0 ]; then
         kernel_file=$(ls images/*vmlinuz | head -n1)
      fi

      ramdisk=$(ls images/*-initrd | head -n1)
      if [ ${#ramdisk} -eq 0 ]; then
          ramdisk=$(ls images/*-loader | head -n1)
      fi

      kernel=$(ls images/*.img | head -n1)

      kid=$(glance -A #{node[:keystone][:admin_token]} add name="${image_name}-kernel" disk_format=aki container_format=aki < ${kernel_file} | cut -d: -f2 | sed 's/ //')
      rid=$(glance -A #{node[:keystone][:admin_token]} add name="${image_name}-initrd" disk_format=ari container_format=ari < ${ramdisk} | cut -d: -f2 | sed 's/ //')
      glance -A #{node[:keystone][:admin_token]} add name="#{img.to_s}-image" disk_format=ami container_format=ami kernel_id=$kid ramdisk_id=$rid < ${kernel}
  EOH
    not_if "glance -A #{node[:keystone][:admin_token]} index | grep #{img.to_s}-image"
  end
end
