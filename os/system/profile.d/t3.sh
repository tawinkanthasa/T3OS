# T3 commands (t3-doctor, t3-get, t3-reset-desktop ...) on the PATH
case ":$PATH:" in *:/usr/share/t3/bin:*) ;; *) PATH="$PATH:/usr/share/t3/bin" ;; esac
