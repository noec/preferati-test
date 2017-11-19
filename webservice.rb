require 'logger'
require 'digest'
require 'savon'
require 'pry'
require 'smarter_csv'
require 'drip'

class WebService
  def csv_records
    SmarterCSV.process('contacts.csv')
  end

  def authenticate_on_sugarcrm
    username = 'aspirant'
    password = Digest::MD5.hexdigest 'Check@t11#'

    begin
      @client = Savon.client(wsdl: 'http://datatest.preferati.net/service/v4_1/soap.php?wsdl')
      response = @client.call(:login, message: { 'user_auth' => {'user_name' => username, 'password' => password }})
      response.body[:login_response][:return][:id]
    rescue Savon::SOAPFault => error
      logger = Logger.new(STDOUT)
      logger.level = Logger::WARN
      logger.error error.http.code
      raise
    end
  end

  def drip_client
    client = Drip::Client.new do |c|
      c.api_key = 'ec94e9d56404d9788d016fe09261dc24'
      c.account_id = '3134701'
    end
  end

  def get_drip_subscribers
    drip_client.subscribers(per_page: 500)
  end

  def get_contact_info_from_drip
    accounts_fields = [
      'phone_office',
      'billing_address_street',
      'billing_address_city',
      'billing_address_state',
      'billing_address_postalcode',
      'billing_address_country'
    ]

    csv_records.each do |record|
      message = {
        'session' => authenticate_on_sugarcrm,
        'module_name' => 'Accounts',
        'query' => "accounts.name = \"#{record[:last_name]}\"",
        'order_by' => '',
        'offset' => '0',
        'select_fields' => accounts_fields,
        'max_results' => '200'
      }

      account = @client.call(:get_entry_list, message: message)
      account = account.body[:get_entry_list_response][:return][:entry_list][:item][:name_value_list][:item]

      drip_subscriber = drip_client.create_or_update_subscriber(record[:email], formatted_drip_subscriber(record, account))
      drip_subscriber_id = drip_subscriber.body['subscribers'].first['id']

      if email_exists?(record[:email])
        logger = Logger.new(STDOUT)
        logger.level = Logger::WARN
        logger.info 'Contact already exists'
        logger.info record[:email]
        logger.info record[:first_name]
        logger.info record[:last_name]
        raise
      else
        contact = prepare_sugarcrm_contact(drip_subscriber.body['subscribers'].first)
        create_sugarcrm_contact(contact)
      end
    end
  end

  def formatted_drip_subscriber(contact, account)
    phone_office = account[0][:value]
    street = account[1][:value]
    city = account[2][:value]
    state = account[3][:value]
    postalcode = account[4][:value]

    billing_address = "#{street}\n#{city}, #{state} #{postalcode}"

    {
      custom_fields: {
        First_Name: contact[:first_name],
        Last_Name: contact[:last_name],
        Address: billing_address,
        Phone: phone_office
      }
    }
  end

  def prepare_sugarcrm_contact(drip_subscriber)
    address = drip_subscriber['custom_fields']['Address']
    street = address.dump.split('\\n').first.delete('\"')
    city = address.dump.split('\\n').last.split(', ').first
    state = address.dump.split('\\n').last.split(', ').last.delete('\"').split(' ').first
    postalcode = address.dump.split('\\n').last.split(', ').last.delete('\"').split(' ').last
    first_name = drip_subscriber['custom_fields']['First_Name']
    last_name = drip_subscriber['custom_fields']['Last_Name']
    phone = drip_subscriber['custom_fields']['Phone']
    email = drip_subscriber['email']
    drip_id = drip_subscriber['id']
    [
      {'name' => 'first_name', 'value' => first_name},
      {'name' => 'last_name', 'value' => last_name},
      {'name' => 'email1', 'value' => email},
      {'name' => 'phone_work', 'value' => phone},
      {'name' => 'primary_address_street', 'value' => street},
      {'name' => 'primary_address_city', 'value' => city},
      {'name' => 'primary_address_state', 'value' => state},
      {'name' => 'primary_address_postalcode', 'value' => postalcode},
      {'name' => 'primary_address_country', 'value' => 'USA'},
      {'name' => 'drip_identifier_c', 'value' => drip_id}
    ]
  end

  def create_sugarcrm_contact(contact)
    message = {
      'session' => authenticate_on_sugarcrm,
      'module_name' => 'Contacts',
      'name_value_list' => contact
    }
    account = @client.call(:set_entry, message: message)
  end

  def email_exists?(email)
    query = "
      contacts.id IN (
      SELECT eabr_scauth.bean_id
      FROM email_addr_bean_rel AS eabr_scauth

      INNER JOIN email_addresses AS ea_scauth
      ON ea_scauth.deleted = 0
      AND eabr_scauth.email_address_id = ea_scauth.id
      AND ea_scauth.email_address_caps = \"#{email}\"

      WHERE eabr_scauth.deleted = 0
      AND eabr_scauth.bean_module = 'Contacts'
      AND eabr_scauth.primary_address = 1
      )
    "
    message = {
      'session' => authenticate_on_sugarcrm,
      'module_name' => 'Contacts',
      'query' => query,
      'deleted' => false
    }
    email = @client.call(:get_entries_count, message: message)

    !email.body[:get_entries_count_response][:return][:result_count].to_i.zero?
  end

end

webservice = WebService.new
webservice.get_contact_info_from_drip
