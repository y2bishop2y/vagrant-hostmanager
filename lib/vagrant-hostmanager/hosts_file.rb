require 'tempfile'

module VagrantPlugins
  module HostManager
    module HostsFile
      def update_guest(machine)
        return unless machine.communicate.ready?

        # download and modify file with Vagrant-managed entries
        file = @global_env.tmp_path.join("hosts.#{machine.name}")
        machine.communicate.download('/etc/hosts', file)
        update_file(file)

        # upload modified file and remove temporary file
        machine.communicate.upload(file, '/tmp/hosts')
        machine.communicate.sudo('mv /tmp/hosts /etc/hosts')
        FileUtils.rm(file)
      end

      def update_host
        # copy and modify hosts file on host with Vagrant-managed entries
        file = @global_env.tmp_path.join('hosts.local')
        FileUtils.cp('/etc/hosts', file)
        update_file(file)

        # copy modified file using sudo for permission
        `sudo cp #{file} /etc/hosts`
      end

      private

      def update_file(file)
        # build array of host file entries from Vagrant configuration
        entries = []
        get_machines.each do |name, p|
          if @provider == p
            machine = @global_env.machine(name, p)
            host = machine.config.vm.hostname || name
            id = machine.id
            ip = get_ip_address(machine)
            aliases = machine.config.hostmanager.aliases.join(' ').chomp
            entries <<  "#{ip}\t#{host} #{aliases}\t# VAGRANT ID: #{id}\n"
          end
        end

        tmp_file = Tempfile.open('hostmanager', @global_env.tmp_path, 'a')
        begin
          # copy each line not managed by Vagrant
          File.open(file).each_line do |line|
            tmp_file << line unless line =~ /# VAGRANT ID:/
          end

          # write a line for each Vagrant-managed entry
          entries.each { |entry| tmp_file << entry }
        ensure
          tmp_file.close
          FileUtils.cp(tmp_file, file)
          tmp_file.unlink
        end
      end


      def get_interface_ip_address(machine)
        
        ip = nil
        # command =  "ip addr list #{machine.config.hostmanager.interface} |grep 'inet ' |cut -d' ' -f6|cut -d/ -f1"
        command = machine.config.hostmanager.interface_ip_command % machine.config.hostmanager.interface

        # Need to create a connection for each machine. Otherwise Vagrant 
        # is cachine these per call
        comm = VagrantPlugins::CommunicatorSSH::Communicator.new(machine)

        comm.sudo(command) do |type, data|
          
          color = type == :stdout ? :green : :red
          @machine.env.ui.info(data.chomp, :color => color, :prefix => false)

          ip = data.chomp
          return ip
        end
      end

      def get_ip_address(machine)
        ip = nil
        if machine.config.hostmanager.ignore_private_ip != true
          machine.config.vm.networks.each do |network|
            key, options = network[0], network[1]
            ip = options[:ip] if key == :private_network
            next if ip
          end
        end
        
        # If the interface has been set and not using private_ip then 
        # determine the assigned DHCP address via method
        if @machine && machine.config.hostmanager.ignore_private_ip == true && machine.config.hostmanger.interface 
          ip = get_interface_ip_address(machine)
        end

        ip || (machine.ssh_info ? machine.ssh_info[:host] : nil)
      end

      def get_machines
        # check if offline machines should be included in host entries
        if @global_env.config_global.hostmanager.include_offline?
          machines = []
          @global_env.machine_names.each do |name|
            begin
              @global_env.machine(name, @provider)
              machines << [name, @provider]
            rescue Vagrant::Errors::MachineNotFound
            end
          end
          machines
        else
          @global_env.active_machines
        end
      end

    end
  end
end
