raise "Synthetic-only seed" unless ENV["SYNTHETIC_DEMO"] == "1"
workbench = Workbench.new
result = workbench.seed!
# Upgrade an existing synthetic volume even when its original seed command was
# already recorded. Both additions retain prior rows and verify replay identity.
DemoScope.transaction do
  DemoScope.where(**workbench.scope).lock.first!
  workbench.product_workspace_service.bootstrap!
  BillingCatalog.new(workbench).seed!
end
puts result.to_json
