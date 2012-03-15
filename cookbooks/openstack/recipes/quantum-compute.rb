#
# Cookbook Name:: openstack
# Recipe:: quantum-server
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

include_recipe "openstack::quantum-common"

# again, we're assuming openvswitch.  this should really go in a separate cookbook

# we need to find out what kernel we're running so we can get the right headers for dkms
kernel_type=`uname -r`.split("-").last.chomp!

[ "linux-headers-#{kernel_type}", "dkms", "openvswitch-datapath-dkms", "openvswitch-switch", "openvswitch-brcompat", "quantum-plugin-openvswitch-agent" ].each do |pkg|
  package pkg do
    action :install
    options "-o Dpkg::Options::='--force-confold' -o Dpkg::Options::='--force-confdef' --force-yes"
  end
end

# probably have some module hackery to do here, but will do that later

service "quantum-plugin-openvswitch-agent" do
  supports :status => true, :restart => true
  action [:enable, :start]
  subscribes :restart, resources(:template => "/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini")
end




