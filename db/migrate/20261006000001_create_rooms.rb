class CreateRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :rooms do |t|
      t.string :code, null: false
      t.json :state, null: false, default: {}
      t.json :players, null: false, default: []
      t.timestamps
    end
    add_index :rooms, :code, unique: true
    add_index :rooms, :updated_at
  end
end
