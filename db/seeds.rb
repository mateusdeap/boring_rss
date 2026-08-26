user = User.find_or_create_by!(email_address: "seed@example.com") do |u|
  u.password = "password"
end

Feed.find_or_create_by(
  user: user,
  title: "Ruby News",
  description: "The latest news from ruby-lang.org.",
  link: "https://www.ruby-lang.org/en/feeds/news.rss"
)
