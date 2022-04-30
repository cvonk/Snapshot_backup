Install "cwRsyncServer 4.1.0 Installer" in "C:\Program Files (x86)\rsyncd"
	acct	backup
	passwd	iw2bipdx

Overwrite the bin folder with the binaries from 5.5.0

Copy "rsyncd.conf" and "rsyncd.secrets" to "C:\Program Files (x86)\rsyncd"

Computer Management > Services and Applications > Services > RsyncServer
	startup type = automatic
	Apply
	Start

I had to add the startup parameter "--start RsyncServer"

Hide the backup user, double click "Hide backup user.reg" to merge the registers settings

