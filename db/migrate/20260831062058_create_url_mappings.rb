class CreateUrlMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :url_mappings do |t|
      t.string :url_code, null: false
      t.string :redirect_url, null: false

      t.timestamps
    end

    add_index :url_mappings, :url_code, unique: true
  end
end
