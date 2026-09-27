# 2026-09-23 baseline for dead-code detection with Vulture.
# This whitelist records current findings rather than reviewing them.
# Any new entries added to this whitelist need a one-line justification.

MAX_EVENTS  # unused variable (plugins/advisor/scripts/advisor_state.py:42)
save_settings  # unused function (plugins/advisor/scripts/advisor_settings.py:194)
save_catalog  # unused function (plugins/advisor/scripts/advisor_catalog.py:330)
reset_selections  # unused function (plugins/advisor/scripts/advisor_settings.py:230)
set_selection  # unused function (plugins/advisor/scripts/advisor_settings.py:306)
_.create_system  # unused attribute (public-release/candidate_inventory.py:245)
_.compress_type  # unused attribute (public-release/candidate_inventory.py:247)
_.handle_starttag  # unused method (public-release/upload_readiness.py:151)
_.redirect_request  # unused method (public-release/upload_readiness.py:180)
fp  # unused variable (public-release/upload_readiness.py:180)
msg  # unused variable (public-release/upload_readiness.py:180)
newurl  # unused variable (public-release/upload_readiness.py:180)
