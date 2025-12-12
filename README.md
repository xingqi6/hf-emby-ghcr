# Media Server for Hugging Face Spaces

A containerized media streaming solution optimized for Hugging Face Spaces deployment with automatic state backup and restore capabilities.

## Features

- 🚀 **Easy Deployment**: One-click deployment to Hugging Face Spaces
- 💾 **Persistent Storage**: Automatic backup and restore via WebDAV
- 🔄 **Auto Sync**: Configurable periodic state synchronization
- 🐳 **Container Based**: Built with Docker for consistency and portability
- 🔒 **Secure**: Environment-based configuration for sensitive data

## Quick Start

### Prerequisites

- GitHub account for building container images
- Hugging Face account for deployment
- WebDAV server for state persistence (optional but recommended)

### Deployment Steps

1. **Fork this repository** to your GitHub account

2. **Configure GitHub Actions**:
   - Go to repository Settings → Actions → General
   - Enable "Read and write permissions" for GITHUB_TOKEN

3. **Build the container image**:
   - Push to main branch or manually trigger the workflow
   - Image will be published to GitHub Container Registry (GHCR)

4. **Deploy to Hugging Face**:
   - Create a new Space on Hugging Face
   - Choose "Docker" as the SDK
   - Upload the `space/` directory contents
   - Configure environment variables (see below)

### Environment Variables

Configure these in your Hugging Face Space settings:

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `APP_PUBLIC_PORT` | Public facing port | No | 7860 |
| `APP_INTERNAL_PORT` | Internal service port | No | 8096 |
| `WEBDAV_URL` | WebDAV server URL | For persistence | - |
| `WEBDAV_USERNAME` | WebDAV authentication username | For persistence | - |
| `WEBDAV_PASSWORD` | WebDAV authentication password | For persistence | - |
| `WEBDAV_BACKUP_PATH` | Remote backup directory path | No | / |
| `SYNC_INTERVAL` | Backup interval in seconds | No | 3600 |
| `KEEP_SNAPSHOTS` | Number of backups to retain | No | 5 |

## Architecture

```
┌─────────────────────────────────────┐
│   Hugging Face Space (Port 7860)   │
├─────────────────────────────────────┤
│  ┌──────────┐      ┌─────────────┐ │
│  │  Proxy   │─────▶│   Service   │ │
│  │ (socat)  │      │  (Port 8096)│ │
│  └──────────┘      └─────────────┘ │
│         │                           │
│  ┌──────▼──────┐                   │
│  │   Backup    │                   │
│  │   Manager   │                   │
│  └──────┬──────┘                   │
└─────────┼────────────────────────────┘
          │
    ┌─────▼─────┐
    │  WebDAV   │
    │  Server   │
    └───────────┘
```

## WebDAV Setup

You can use various WebDAV providers:

- **Koofr**: Free tier available, easy setup
- **Box**: 10GB free storage
- **pCloud**: 10GB free, good reliability
- **Self-hosted**: NextCloud, ownCloud, etc.

Example configuration for Koofr:
```
WEBDAV_URL=https://app.koofr.net/dav
WEBDAV_USERNAME=your_email@example.com
WEBDAV_PASSWORD=your_app_password
WEBDAV_BACKUP_PATH=/backups/mediaserver
```

## Backup System

The backup system automatically:
- Creates compressed snapshots of application state
- Uploads to WebDAV server at configured intervals
- Restores latest backup on container start
- Maintains configured number of historical backups
- Runs silently in the background

Backup files are named: `backup_YYYYMMDD_HHMMSS.tar.gz`

## Troubleshooting

### Container fails to start
- Check all required environment variables are set
- Verify WebDAV credentials if using persistence
- Ensure GitHub image was built successfully

### State not persisting
- Verify WebDAV connectivity
- Check WEBDAV_URL format (must include https://)
- Confirm credentials have write permissions
- Review Space logs for error messages

### Service not accessible
- Ensure APP_PUBLIC_PORT is set to 7860
- Check if Space is running (not sleeping)
- Verify the Space URL is correct

## Development

### Local Testing

```bash
# Build the image
cd image
docker build -t media-server:local .

# Run with environment variables
docker run -p 7860:7860 \
  -e WEBDAV_URL=https://your-webdav-server.com \
  -e WEBDAV_USERNAME=user \
  -e WEBDAV_PASSWORD=pass \
  media-server:local
```

### Customization

- Modify `image/Dockerfile` to change base configuration
- Update `image/entrypoint.sh` for startup behavior
- Edit `image/backup.py` to adjust backup logic

## Security Notes

- Never commit credentials to the repository
- Use Hugging Face Secrets for sensitive variables
- WebDAV password should be an app-specific password
- Regularly rotate access credentials
- Keep backup retention reasonable (5-10 snapshots)

## License

This project is provided as-is for personal and educational use.

## Support

For issues or questions:
- Check existing GitHub Issues
- Review Hugging Face Spaces documentation
- Verify WebDAV provider documentation

## Acknowledgments

Built for deployment on Hugging Face Spaces infrastructure.
