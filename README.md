freehck.script_with_locks
=========

This role copies the script that run any command with specified lock.

Very useful for crontab jobs. Run it with `--help` to learn the options.

Role Variables
--------------
`with_locks_script_dir`: directory to install the script, default "/opt/scripts"

`with_locks_script_name`: script name, default "with-locks"

Example Playbook
----------------

    - hosts:
        - database
      become: yes
	  vars:
	    lockfile: "/var/lock/db-update-index.lock"
		logfile: "/var/log/db-update-index.log"
      roles:
        - role: freehck.script_with_locks
		- role: freehck.crontask
		  crontask_file: "database"
		  crontask_name: "update index"
		  crontask_minute: "*/30"
		  crontask_user: "root"
		  crontask_job: "/opt/scripts/with-locks --timestamp --pid --highlight-errors --silent --lock {{ lockfile }} --log {{ logfile }} -- /opt/scripts/perform_update_index.sh"
		  # or the same without long options:
		  # crontask_job: "/opt/scripts/with-locks -tpes -l {{ lockfile }} -j {{ logfile }} -- /opt/scripts/perform_update_index.sh"

License
-------
MIT

Author Information
------------------
Dmitrii Kashin, <freehck@freehck.ru>
