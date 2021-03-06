test_name "#4124: should list all disabled services on Redhat/CentOS"
step "Validate disabled services agreement ralsh vs. OS service count"
# This will remotely exec:
# ticket_4124_should_list_all_disabled.sh

hosts.each do |host|
  unless host['platform'].include? 'centos' or host['platform'].include? 'redhat'
    skip_test "Test not supported on this plaform"
   else
    run_script_on(host,'tests/acceptance/resource/service/ticket_4124_should_list_all_disabled.sh')
  end
end
