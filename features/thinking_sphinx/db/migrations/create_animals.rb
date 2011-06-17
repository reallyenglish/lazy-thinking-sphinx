ActiveRecord::Base.connection.create_table :animals, :force => true do |t|
  t.column :name,   :string,  :null => false
  t.column :type,   :string
end
