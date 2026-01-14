export function updateFilterLinks(controller) {
  const links = controller.element.querySelectorAll("a[data-turbo-frame='character_picker']")
  links.forEach(link => {
    const url = new URL(link.href)

    url.searchParams.delete("selected[]")

    controller.selectedValue.forEach(id => {
      url.searchParams.append("selected[]", id)
    })

    link.href = url.toString()
  })
}
