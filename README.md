# ansible-role-servermonkey-winrun

Run Windows GUI applications via Cygwin

Example usage:

```
- include_role: name=servermonkey.winrun
  vars:
    winrun_path: 'C:/WINDOWS/system32/cmd.exe'
    winrun_args: '/c exit'
  when: '"CYGWIN" in ansible_os_family'
```

```
- include_role: name=servermonkey.winrun
  vars:
    winrun_path: 'msiexec.exe'
    winrun_args: '/i \"C:\\opt\\hello_world.msi\" /quiet /passive /norestart'
  when: '"CYGWIN" in ansible_os_family'
```
