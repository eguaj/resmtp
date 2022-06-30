
Fake SMTP server to relay any message to a specific mail account via a specific
MTA.

# Usage

    $ perl resmtp.pl \
      [-d|--daemon] \
      [-h|--host <listen_host>] \
      [-p|--port <listen_port>] \
      [-t|--timeout <timeout_in_seconds>] \
      [-b|--blackhole] \
      [-f|--from <smtp.mail.from@example.net>] \
      <recipient@example.net> [<smtp_host[:port]>]

# Sample systemd service file

    # cat <<'EOF' > /usr/lib/systemd/system/resmtp.service
    [Unit]
    Description=resmtp Service
    After=network.target
    
    [Service]
    Type=simple
    ExecStart=/usr/local/bin/resmtp.pl --host 127.0.0.1 --port 25 recipient@example.net
    Restart=on-abort
    
    [Install]
    WantedBy=multi-user.target
    EOF
    # systemctl enable resmtp
    # systemctl start resmtp
 
