raise 'Synthetic local worker only' unless ENV['SYNTHETIC_DEMO']=='1'
$stdout.sync=true
stop=false
Signal.trap('TERM') { stop=true }; Signal.trap('INT') { stop=true }
until stop
  item=BillingWorker.perform_one
  sleep 1 unless item
end
