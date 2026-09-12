# ============================================================
# Rolle manager-backup – Backup-Config-Manager
#  Identisch zur Rolle manager, aber:
#   * CAPsMAN passiv (Netwatch auf den Primary übernimmt nach ~3 min)
#   * cfm-mgr spiegelt den Primary (live/, archive/, meta/, state/) und
#     verweigert Releases, bis er per $cfmPromoteManager befördert wurde.
# ============================================================
:global cfmDl
:global cfmIsBackup true
/import file-name=($cfmDl . "/roles/manager.rsc") verbose=no
:set cfmIsBackup false
