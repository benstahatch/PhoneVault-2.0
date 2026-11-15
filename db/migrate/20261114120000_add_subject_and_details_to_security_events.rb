class AddSubjectAndDetailsToSecurityEvents < ActiveRecord::Migration[8.1]
  def change
    # which device, backup run, or file the event is about. No foreign key on purpose:
    # a security log keeps its rows (and what they pointed at) even after records are deleted.
    add_reference :security_events, :subject, polymorphic: true, null: true, index: true

    # a readable snapshot written when the event happens, such as "IMG_2041.png from Jordan's iPhone",
    # so later renames or deletions don't change what the log says
    add_column :security_events, :details, :string, limit: 255
  end
end
