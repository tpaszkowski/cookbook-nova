#
# Cookbook Name:: nova
# Recipe:: nova-network
#
# Copyright 2012, Rackspace US, Inc.
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

class ::Chef::Recipe
  include ::Openstack
end

next_vlan = 100
node["nova"]["networks"].each do |net|
  execute "nova-manage network create --label=#{net['label']}" do
    # The only two required keys in each network Hash
    # are "label" and "ipv4_cidr".
    cmd = "nova-manage network create --label=#{net['label']} --fixed_range_v4=#{net['ipv4_cidr']}"
    if net.has_key?("multi_host")
        cmd += " --multi_host='#{net['multi_host']}'"
    end
    if net.has_key?("num_networks")
        cmd += " --num_networks=#{net['num_networks']}"
    end
    if net.has_key?("network_size")
        cmd += " --network_size=#{net['network_size']}"
    end
    if net.has_key?("bridge")
        cmd += " --bridge=#{net['bridge']}"
    end
    # Older attributes have the key as "bridge_dev" instead
    # of "bridge_interface"...
    if net.has_key?("bridge_interface") or net.has_key?("bridge_dev")
        val = net.has_key?("bridge_interface") ? net["bridge_interface"] : net["bridge_dev"]
        cmd += " --bridge_interface=#{val}"
    end
    if net.has_key?("dns1")
        cmd += " --dns1=#{net['dns1']}"
    end
    if net.has_key?("dns2")
        cmd += " --dns2=#{net['dns2']}"
    end
    if net.has_key?("vlan")
        cmd += " --vlan=#{net['vlan']}"
    elsif node["nova"]["network"]["network_manager"] == "nova.network.manager.VlanManager"
        cmd += " --vlan=#{next_vlan}"
        next_vlan = next_vlan + 1
    end

    command cmd
    not_if "nova-manage network list | grep #{net['ipv4_cidr']}"

    action :run
  end
end

cookbook_file node["nova"]["floating_cmd"] do
  source "add_floaters.py"
  mode   00755

  action :create
end

floating = node["nova"]["network"]["floating"]
if floating && (floating["ipv4_cidr"] || floating["ipv4_range"])
  cmd = ""
  if floating["ipv4_cidr"]
    cmd = "#{node["nova"]["floating_cmd"]} --cidr=#{floating["ipv4_cidr"]}"
  elsif floating["ipv4_range"]
    cmd = "#{node["nova"]["floating_cmd"]} --ip-range=#{floating["ipv4_range"]}"
  end

  execute "nova-manage floating create" do
    command cmd

    not_if "nova-manage floating list |grep -E '.*([0-9]{1,3}[\.]){3}[0-9]{1,3}*'"

    action :run
  end
end
