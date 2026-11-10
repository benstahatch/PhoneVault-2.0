# Tailwind classes that make a link look like a button, matching the dashboard's "Your devices" button.
# Use them as: link_to "Upload", path, class: button_classes
module ButtonsHelper
  BUTTON_BASE = "inline-flex box-border items-center justify-center rounded-lg font-semibold no-underline " \
                "transition-colors duration-150 focus-visible:outline-2 focus-visible:outline-offset-4 " \
                "focus-visible:outline-neutral-900 motion-reduce:transition-none".freeze

  BUTTON_STYLES = {
    # dark button for the main action on a page
    primary: "bg-[#171717] text-white hover:bg-[#e66b00] hover:text-white",
    # white outlined button for secondary actions like "Back"
    secondary: "border border-neutral-300 bg-white text-neutral-900 hover:border-[#e66b00] hover:text-[#c45a00]"
  }.freeze

  BUTTON_SIZES = {
    normal: "min-h-12 px-5 py-3 text-sm",
    small: "min-h-10 px-4 py-2 text-sm"
  }.freeze

  def button_classes(style = :primary, size: :normal)
    [ BUTTON_BASE, BUTTON_STYLES.fetch(style), BUTTON_SIZES.fetch(size) ].join(" ")
  end
end
