# Tailwind classes shared by PhoneVault's form fields, so every form looks the same.
module FormStylesHelper
  def field_classes
    "block box-border w-full rounded-lg border border-neutral-300 bg-white px-3 py-2.5 text-neutral-900 " \
      "focus:border-orange-600 focus:outline-2 focus:outline-orange-600"
  end

  def label_classes
    "mb-2 block text-sm font-medium text-neutral-700"
  end

  # file inputs style their "Choose file" button with Tailwind's file: prefix
  def file_field_classes
    "block box-border w-full rounded-lg border border-neutral-300 bg-white p-2 text-sm text-neutral-700 " \
      "file:mr-4 file:cursor-pointer file:rounded-lg file:border-0 file:bg-[#171717] file:px-4 file:py-2 " \
      "file:font-semibold file:text-white hover:file:bg-[#e66b00] focus:outline-2 focus:outline-orange-600"
  end
end
