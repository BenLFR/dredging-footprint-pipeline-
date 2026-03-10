# Generic HPC Setup

## Local prerequisites

- `bash`
- `ssh`
- `rsync`
- access to a Slurm-based cluster

## Recommended setup sequence

1. Create `deploy/config.env` from `deploy/config.example.env`.
2. Configure SSH outside the repository.
3. Keep SSH keys and SSH config files private.
4. Validate the environment with:

```bash
bash deploy/preflight_hpc.sh --ping
```

## Notes

- Public documentation uses placeholders only. Do not commit site-specific credentials or paths.
- If your site requires a custom SSH config file, set `SSH_CONFIG_FILE` in `deploy/config.env`.
- If your site uses modules or containers, encode them in Slurm templates rather than in ad hoc shell history.
