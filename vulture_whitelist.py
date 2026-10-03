# Vulture whitelist: every entry names its dynamic caller or the test that is its only caller.
# Any new entries added to this whitelist need a one-line justification.

# Legacy saved-state stack: no production caller, exercised by plugins/advisor/tests/test_advisor_config.py.
# Retirement is a pending product decision (see TASKS.md / audit F5), so the API stays until then.
save_settings  # advisor_settings.py: test_advisor_config.py (revision-conflict and reset tests)
reset_selections  # advisor_settings.py: test_advisor_config.py (saved-selection reset)
set_selection  # advisor_settings.py: test_advisor_config.py (saved-selection write)

# Standard-library attribute writes and subclass hooks in public-release tooling.
_.create_system  # candidate_inventory.py: zipfile.ZipInfo attribute assignment for reproducible ZIPs
_.compress_type  # candidate_inventory.py: zipfile.ZipInfo attribute assignment
_.handle_starttag  # upload_readiness.py: html.parser.HTMLParser hook invoked by feed()
_.redirect_request  # upload_readiness.py: urllib.request.HTTPRedirectHandler hook
fp  # redirect_request parameter required by the urllib signature
msg  # redirect_request parameter required by the urllib signature
newurl  # redirect_request parameter required by the urllib signature
