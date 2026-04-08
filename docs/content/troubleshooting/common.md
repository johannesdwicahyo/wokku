# Common Issues

## Deploy Fails

- **Check build logs** — go to Deploys tab for error details
- **Missing Procfile** — ensure your repo has a `Procfile` defining process types
- **Buildpack not detected** — add a `Dockerfile` or ensure language detection files exist
- **Out of memory** — upgrade your dyno tier

## App Not Accessible

- **Check domains** — verify DNS points to your server
- **Check SSL** — ensure SSL is enabled after DNS propagation
- **Health checks failing** — check the health check path returns 200
- **App stopped** — restart the app from the dashboard

## Database Connection Issues

- **Check linking** — verify the database is linked to your app
- **Check env vars** — `DATABASE_URL` should be set automatically when linked
- **Wrong credentials** — unlink and re-link the database

## SSH Connection Failed

- **Check SSH key** — ensure the private key matches the server
- **Check hostname** — verify the server hostname or IP
- **Check port** — default is 22, some servers use custom ports
- **Firewall** — ensure port 22 is open on the server

## Push Rejected

- **Wrong branch** — push to the correct deploy branch
- **SSH keys** — add your SSH key to your Wokku account
- **App doesn't exist** — create the app first before pushing
