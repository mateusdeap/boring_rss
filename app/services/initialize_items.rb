class InitializeItems
  def initialize(parsed_items)
    @parsed_items = parsed_items
  end

  def call
    @parsed_items.map do |item|
      Item.new(
        title: item.title,
        description: item.description,
        link: item.link
      )
    end
  end
end
