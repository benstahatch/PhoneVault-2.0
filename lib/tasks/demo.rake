namespace :phonevault do
  desc "Create a demo account with devices and backups (set DEMO_PASSWORD to choose the password)"
  task demo: :environment do
    result = DemoData.new.create(password: ENV["DEMO_PASSWORD"])

    if result.created
      puts "Created the demo account."
      puts "  username: #{DemoData::USERNAME}"
      puts "  password: #{result.password}"
      puts "The password is only shown now. Remove the account later with: bin/rails phonevault:demo:reset"
    else
      puts "The demo account already exists. Start over with: bin/rails phonevault:demo:reset"
    end
  end

  namespace :demo do
    desc "Delete the demo account, its backups, and its stored files"
    task reset: :environment do
      if DemoData.new.reset
        puts "Deleted the demo account and its backups."
      else
        puts "There is no demo account."
      end
    end
  end
end
