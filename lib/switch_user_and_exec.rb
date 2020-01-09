require 'etc'

current_shell_user = Etc.getpwuid
current_shell_username = current_shell_user.name

if current_shell_user.name == 'root' && (developer_uid = ENV['DEVELOPER_UID'])
  new_shell_user = Etc.getpwuid(developer_uid.to_i)

  if new_shell_user.uid != current_shell_user.uid
    new_shell_username = new_shell_user.name
    print "Running command as '#{new_shell_username}' "
    puts "instead of '#{current_shell_username}'..."
    exec 'su-exec', new_shell_username, $0, *$*
  end
end
