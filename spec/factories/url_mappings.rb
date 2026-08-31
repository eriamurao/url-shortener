FactoryBot.define do
  factory :url_mapping do
    url_code { Faker::Alphanumeric.alphanumeric(number: 10) }
    redirect_url { Faker::Internet.url }
  end
end
