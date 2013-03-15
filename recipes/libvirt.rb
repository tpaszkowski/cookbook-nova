#
# Cookbook Name:: nova
# Recipe:: libvirt
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

platform_options = node["nova"]["platform"]

platform_options["libvirt_packages"].each do |pkg|
  package pkg do
    action :install
  end
end

def set_boot_kernel_and_trigger_reboot(flavor='default')
  # only default and xen flavor is supported by this helper right now
  default_boot, current_default = 0, nil

  # parse menu.lst, to find boot index for selected flavor
  File.open('/boot/grub/menu.lst') do |f|
    f.lines.each do |line|
      current_default = line.scan(/\d/).first.to_i if line.start_with?('default')

      if line.start_with?('title')
        if flavor.eql?('xen')
          # found boot index
          break if line.include?('Xen')
        else
          # take first kernel as default, unless we are searching for xen
          # kernel
          break
        end
        default_boot += 1
      end
    end
  end

  # change default option for /boot/grub/menu.lst
  unless current_default.eql?(default_boot)
    puts "changed grub default to #{default_boot}"
    %x[sed -i -e "s;^default.*;default #{default_boot};" /boot/grub/menu.lst]
  end

  # trigger reboot through reboot_handler, if kernel-$flavor is not yet
  # running
  unless %x[uname -r].include?(flavor)
    node.run_state[:reboot] = true
  end
end

# on suse nova-compute don't depends on any virtualization mechanism
case node["platform"]
when "suse"
  case node["nova"]["libvirt"]["virt_type"]
  when "kvm"
    node["nova"]["platform"]["kvm_packages"].each do |pkg|
      package pkg do
        action :install
      end
    end
    execute "loading kvm modules" do
      command "grep -q vmx /proc/cpuinfo && /sbin/modprobe kvm-intel; grep -q svm /proc/cpuinfo && /sbin/modprobe kvm-amd; /sbin/modprobe vhost-net"
    end

  when "xen"
    node["nova"]["platform"]["xen_packages"].each do |pkg|
      package pkg do
        action :install
      end
    end
    set_boot_kernel_and_trigger_reboot('xen')

  when "qemu"
    node["nova"]["platform"]["kvm_packages"].each do |pkg|
      package pkg do
        action :install
      end
    end

  when "lxc"
    node["nova"]["platform"]["lxc_packages"].each do |pkg|
      package pkg do
        action :install
      end
    end
    service "boot.cgroup" do
      action [:enable, :start]
    end
  end
end


# oh fedora...
bash "create libvirtd group" do
  cwd "/tmp"
  user "root"
  code <<-EOH
    groupadd -f libvirtd
    usermod -G libvirtd nova
  EOH

  only_if { platform? %w{fedora redhat centos} }
end

group "libvirt" do
  append true
  members ["openstack-nova"]

  action :create
  only_if { platform? %w{suse} }
end

# oh redhat
# http://fedoraproject.org/wiki/Getting_started_with_OpenStack_EPEL#Installing_within_a_VM
# ln -s /usr/libexec/qemu-kvm /usr/bin/qemu-system-x86_64
link "/usr/bin/qemu-system-x86_64" do
  to "/usr/libexec/qemu-kvm"

  only_if { platform? %w{fedora redhat centos} }
end

service "dbus" do
  action [:enable, :start]
end

service "libvirt-bin" do
  service_name platform_options["libvirt_service"]
  supports :status => true, :restart => true

  action [:enable, :start]
end

execute "Disabling default libvirt network" do
  command "virsh net-autostart default --disable"

  only_if "virsh net-list | grep -q default"
end

execute "Deleting default libvirt network" do
  command "virsh net-destroy default"

  only_if "virsh net-list | grep -q default"
end

# TODO(breu): this section needs to be rewritten to support key privisioning
template "/etc/libvirt/libvirtd.conf" do
  source "libvirtd.conf.erb"
  owner  "root"
  group  "root"
  mode   00644
  variables(
    :auth_tcp => node["nova"]["libvirt"]["auth_tcp"],
    :unix_sock_group => node["nova"]["libvirt"]["unix_sock_group"]
  )

  notifies :restart, "service[libvirt-bin]", :immediately
  not_if { platform? "suse" }
end

template "/etc/default/libvirt-bin" do
  source "libvirt-bin.erb"
  owner  "root"
  group  "root"
  mode   00644

  notifies :restart, "service[libvirt-bin]", :immediately

  only_if { platform? %w{ubuntu debian} }
end

template "/etc/sysconfig/libvirtd" do
  source "libvirtd.erb"
  owner  "root"
  group  "root"
  mode   00644

  notifies :restart, "service[libvirt-bin]", :immediately

  only_if { platform? %w{fedora redhat centos} }
end
