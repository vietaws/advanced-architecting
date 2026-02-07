# Check systemd service status
sudo systemctl status demo-app

# Check application logs
sudo journalctl -u demo-app -f

# Restart service if needed
sudo systemctl restart demo-app

# Enable service on boot
sudo systemctl enable demo-app

# Check if port 3000 is listening
sudo netstat -tlnp | grep 3000

# Kill all processes on port 3000
sudo lsof -ti:3000 | xargs sudo kill -9