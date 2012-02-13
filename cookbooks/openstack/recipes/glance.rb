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

template "/etc/glance/glance-registry.conf" do
  source "glance-registry.conf.erb"
  owner "root"
  group "root"
  mode "0644"
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
  owner "root"
  group "root"
  mode "0644"
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
  owner "root"
  group "root"
  mode "0644"
  variables(
    :user => node[:glance][:db_user],
    :passwd => node[:glance][:db_passwd],
    :ip_address => node[:controller_ipaddress],
    :db_name => node[:glance][:db]
  )
end

template "/etc/glance/glance-api-paste.ini" do
  source "glance-api-paste.ini.erb"
  owner "root"
  group "root"
  mode "0644"
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
  owner "root"
  group "root"
  mode "0644"
  variables(
    :ip_address => node[:controller_ipaddress],
    :service_port => node[:keystone][:service_port],
    :admin_port => node[:keystone][:admin_port],
    :admin_token => node[:keystone][:admin_token]
  )
  notifies :restart, resources(:service => "glance-registry"), :immediately
end

template "/etc/glance/policy.json" do
  source "policy.json.erb"
  owner "root"
  group "root"
  mode "0644"
  notifies :restart, resources(:service => "glance-api"), :immediately
end
 

bash "default image setup" do
  cwd "/tmp"
  user "root"
  code <<-EOH
      mkdir images
      curl #{node[:image][:natty]} | tar -zx -C images/
      glance -A #{node[:keystone][:admin_token]} add name="ubuntu-11.04-kernel" disk_format=aki container_format=aki < images/natty-server-uec-amd64-vmlinuz-virtual
      glance -A #{node[:keystone][:admin_token]} add name="ubuntu-11.04-initrd" disk_format=ari container_format=ari < images/natty-server-uec-amd64-loader
      glance -A #{node[:keystone][:admin_token]} add name="ubuntu-11.04-server" disk_format=ami container_format=ami kernel_id=1 ramdisk_id=2 < images/natty-server-uec-amd64.img

  EOH
  # not_if do File.exists?("/var/lib/glance/images/3") end
  not_if "glance -A #{node[:keystone][:admin_token]} index | grep ubuntu-11.04"
end
