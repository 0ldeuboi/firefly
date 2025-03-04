# Firefly III & Data Importer Installer

This script automates the installation and updating of Firefly III (a personal finance manager) and its Data Importer companion on Ubuntu 20.04 or higher systems.

## Features

- **Complete Installation**: Installs and configures Firefly III, its Data Importer, and all dependencies
- **Automatic Updates**: Detects and updates existing installations
- **SSL Support**: Configures Let's Encrypt SSL certificates for secure connections
- **Database Setup**: Configures MySQL or SQLite databases
- **PHP Compatibility**: Ensures PHP compatibility with the installed Firefly III version
- **Interactive & Non-Interactive Modes**: Run with or without user prompts
- **Comprehensive Logging**: Detailed logs for troubleshooting
- **Backup Creation**: Creates backups before updating existing installations
- **Credentials Management**: Securely stores installation credentials
- **Progress Indicators**: Visual progress tracking for long-running operations
- **Enhanced Error Messages**: Detailed error messages with troubleshooting steps
- **Input Validation**: Validates email addresses, domain names, and other inputs
- **Automatic Recovery**: Offers to restore from backup if updates fail

## Installation

### Quick Start

1. Download the script:
   ```bash
   wget -O firefly-iii_install-update.sh blob:https://github.com/7c73d8ce-e65c-4a80-b7f7-4a5977918297
   ```

2. Make it executable:
   ```bash
   chmod +x firefly-iii_install-update.sh
   ```

3. Run with sudo or as root:
   ```bash
   sudo ./firefly-iii_install-update.sh
   ```

### Installation Modes

The script offers three main modes of operation:

1. **Interactive Mode**: Prompts for all configuration options with input validation
2. **Non-Interactive Mode**: Uses default values or environment variables
3. **Menu Mode**: Access detailed information about available options

When you start the script, you'll have 30 seconds to select a mode:
- Press `M` to view the Menu
- Press `I` to use Interactive mode
- Press `C` to cancel the installation
- Press [Enter] to use Non-Interactive mode

### What to Expect During Installation

The installation process now includes:

1. **Progress Indicators**: Visual feedback showing completion percentage for long-running tasks
2. **Step-by-Step Information**: Clear messages about what the script is currently doing
3. **Input Validation**: Automatic checks for valid domain names, email addresses, and numeric inputs
4. **Automatic Recovery**: If an update fails, the script will offer to restore from backup

### Environment Variables for Non-Interactive Mode

You can use the following environment variables to customize your installation when running in non-interactive mode:

| Variable | Description | Default | Validation |
|----------|-------------|---------|------------|
| `NON_INTERACTIVE` | Set to `true` for non-interactive mode | `false` | None |
| `HAS_DOMAIN` | Set to `true` if you have a domain name | `false` | Boolean check |
| `DOMAIN_NAME` | Your domain name (e.g., example.com) | Required if `HAS_DOMAIN=true` | Format validation |
| `EMAIL_ADDRESS` | Email for SSL certificate registration | Required if `HAS_DOMAIN=true` | Format validation |
| `DB_NAME` | Database name | Random generated name | Sanitized |
| `DB_USER` | Database username | Random generated name | Sanitized |
| `DB_PASS` | Database password | Random generated password | None |
| `CRON_HOUR` | Hour (0-23) to run daily cron job | `3` (3 AM) | Range check (0-23) |
| `GITHUB_TOKEN` | GitHub API token to avoid rate limiting | None | None |
| `PHP_VERSION` | Specific PHP version to install | Latest available | Format check |

Example:
```bash
NON_INTERACTIVE=true HAS_DOMAIN=true DOMAIN_NAME=finance.example.com EMAIL_ADDRESS=admin@example.com DB_NAME=firefly DB_USER=fireflyuser DB_PASS=secure_password CRON_HOUR=4 sudo ./firefly-iii_install-update.sh
```

## Post-Installation

After installation completes, you'll find:

1. **Access URLs**:
   - Firefly III: `http://your-server-ip/` or `https://your-domain/`
   - Data Importer: `http://your-server-ip:8080/` or `https://importer.your-domain/`

2. **Configuration Files**:
   - Firefly III: `/var/www/firefly-iii/.env`
   - Data Importer: `/var/www/data-importer/.env`

3. **Credentials**:
   - Saved in `/root/firefly_credentials.txt`
   - May be encrypted if you chose to set a password

### Verifying Installation Success

To verify your installation completed successfully:

1. **Check Firefly III Access**:
   ```bash
   curl -I http://your-server-ip/ 
   # or for SSL:
   curl -I https://your-domain/
   ```
   
   You should see a `HTTP/1.1 200 OK` response.

2. **Check Data Importer Access**:
   ```bash
   curl -I http://your-server-ip:8080/
   # or for SSL:
   curl -I https://importer.your-domain/
   ```

3. **Verify Apache Configuration**:
   ```bash
   apachectl configtest
   ```
   
   You should see: `Syntax OK`

4. **Check PHP Version**:
   ```bash
   php -v
   ```

## Updating

To update an existing installation, simply run the script again:

```bash
sudo ./firefly-iii_install-update.sh
```

The script will:
1. Detect your current installation
2. Back up your existing installation
3. Download and install the latest version
4. Migrate your database and configuration

If the update process fails for any reason, the script will offer to restore from the backup automatically.

## Troubleshooting

### Progress and Error Information

The script now provides real-time progress indicators for long-running tasks and detailed error messages with troubleshooting advice. If you encounter an issue, the script will:

1. Display a descriptive error message with specific causes
2. Provide suggested troubleshooting steps
3. Offer recovery options when possible

### Log Files

The script creates detailed logs in `/var/log/firefly_install_*.log`. Check these logs if you encounter any issues.

### Common Issues and Solutions

1. **Database Connection Errors**:
   - Verify MySQL/MariaDB is running: `systemctl status mysql`
   - Check database credentials in the respective `.env` files
   - Ensure you have sufficient privileges: `mysql -u root -p -e "SHOW GRANTS FOR 'your_user'@'localhost';"`
   - Verify database exists: `mysql -u root -p -e "SHOW DATABASES;"`

2. **Apache Configuration Issues**:
   - Run: `apachectl configtest` to identify syntax errors
   - Check Apache logs: `tail -f /var/log/apache2/error.log`
   - Verify port configurations in `/etc/apache2/ports.conf`
   - Check site configurations in `/etc/apache2/sites-available/`

3. **PHP Version Compatibility**:
   - Check installed PHP version: `php -v`
   - Verify compatibility with Firefly III requirements
   - If needed, install a specific PHP version: `apt-get install php8.1`
   - Check enabled PHP modules: `php -m`

4. **SSL Certificate Problems**:
   - Ensure your domain points to the server's IP address: `dig +short yourdomain.com`
   - Check DNS propagation: `nslookup yourdomain.com`
   - Check Certbot logs: `journalctl -u certbot`
   - Verify firewall allows ports 80 and 443: `ufw status`

5. **Input Validation Failures**:
   - Ensure email addresses follow standard format: `user@example.com`
   - Domain names should be properly formatted: `example.com` or `sub.example.com`
   - Numeric inputs must be within their valid ranges (e.g., cron hour: 0-23)

## Security Considerations

1. The script saves database credentials in `/root/firefly_credentials.txt`
   - This file is only readable by root by default
   - The script offers GPG encryption for this file in interactive mode
   - You can safely delete this file after installation if you've saved the credentials elsewhere

2. The script configures firewall rules for ports 80, 443, and 8080
   - Consider restricting access if needed using additional UFW rules
   - For example: `ufw allow from 192.168.1.0/24 to any port 8080`

3. Database credentials are stored in `.env` files
   - These files are automatically set with 640 permissions (readable only by root and www-data)
   - The script validates and secures file permissions during installation

4. Input validation helps prevent common security issues
   - Email addresses and domain names are validated before use
   - Numeric inputs are checked to prevent unexpected behavior

## Uninstallation

To uninstall:

1. Remove the Apache configurations:
   ```bash
   sudo a2dissite firefly-iii firefly-importer
   sudo rm /etc/apache2/sites-available/firefly-iii.conf
   sudo rm /etc/apache2/sites-available/firefly-importer.conf
   sudo systemctl reload apache2
   ```

2. Remove the cron job:
   ```bash
   sudo rm /etc/cron.d/firefly-iii-cron
   ```

3. Remove the installation directories:
   ```bash
   sudo rm -rf /var/www/firefly-iii /var/www/data-importer
   ```

4. Drop the database (if using MySQL):
   ```bash
   mysql -u root -p -e "DROP DATABASE your_firefly_database_name;"
   ```

## License

This script is provided under an open-source license.

## Acknowledgments

- Firefly III is developed by [JC5](https://github.com/JC5)
- This installer script is not officially affiliated with the Firefly III project

---

For more information about Firefly III itself, visit the [official documentation](https://docs.firefly-iii.org/).