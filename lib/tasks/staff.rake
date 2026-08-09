# frozen_string_literal: true

# Platform staff management. Deliberately a task rather than a UI action:
# granting cross-tenant access should be an explicit, logged act performed
# from a shell, not a button someone can reach by accident.
namespace :staff do
  desc "Grant platform staff access: rake 'staff:grant[email@example.com]'"
  task :grant, [ :email ] => :environment do |_t, args|
    email = args[:email].to_s.strip.downcase
    abort "usage: rake 'staff:grant[email@example.com]'" if email.blank?

    user = User.find_by(email_address: email)
    abort "no user with email #{email}" if user.nil?

    staff = StaffMember.find_or_initialize_by(user: user)
    staff.status = "active"
    staff.revoked_at = nil
    staff.granted_at ||= Time.current
    staff.save!

    puts "granted platform staff access to #{email}"
    puts "admin UI: /admin"
  end

  desc "Revoke platform staff access: rake 'staff:revoke[email@example.com]'"
  task :revoke, [ :email ] => :environment do |_t, args|
    email = args[:email].to_s.strip.downcase
    staff = StaffMember.joins(:user).find_by(users: { email_address: email })
    abort "no staff member with email #{email}" if staff.nil?

    staff.update!(status: "revoked", revoked_at: Time.current)
    puts "revoked platform staff access for #{email}"
  end

  desc "List platform staff"
  task list: :environment do
    StaffMember.includes(:user).find_each do |s|
      puts format("%-40s %-10s granted %s", s.user.email_address, s.status, s.granted_at)
    end
  end
end
