require 'pry'
require 'mysql'

class Contact < ActiveRecord::Base
  @mysql = Mysql.new('138.197.68.17', 'aspirant', 'dPva6gkea,=p~fZz', 'interview')

  def save_drip_id(id, drip_id)
    drip_id ||= drip_id
    mysql = @mysql.prepare("UPDATE contacts SET drip_id = \"#{drip_id}\" WHERE id = \"#{id}\";")
    mysql.execute
  end
end
