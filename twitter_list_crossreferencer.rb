require 'net/http'
require 'json'

# Quit with usage error message
def quit_with_usage_error
  quit_with_error( "USAGE: ruby list_checker.rb <SCREEN_NAME>" )
end

# Quit on error, display error message
def quit_with_error( error_msg )
  puts error_msg
  exit  
end

puts "*** Twitter User List Crossreferencer ***"

# Get the screen name to crossreference
source_screen_name = ARGV[0]
quit_with_usage_error unless source_screen_name
puts "Finding users similar to @#{source_screen_name}"

# Twitter only accepts 150 request per hour.
# Some very popular users will exceed this.
TWITTER_RATE_LIMIT = 150  
requests_remaining = TWITTER_RATE_LIMIT

# Download all of the lists that include the source user
# Twitter sends 20 per page, so we need to request multiple times with 'cursor'
membership_lists = Array.new
cursor = -1
while true do
  # Request Twitter list membership
  begin
    result = Net::HTTP.get( URI( "http://api.twitter.com/1/lists/memberships.json?screen_name=#{source_screen_name}&cursor=#{cursor}" ) )
    json_result = JSON.parse( result )
    requests_remaining -= 1 # Decrement the number of remaining Twitter requests   
  end
  
  quit_with_error( json_result["error"] ) if json_result["error"] # Check for errors    
    
  # Append the downloaded lists     
  membership_lists << json_result["lists"]
    
  # Check if we need to download another set of lists
  if json_result["next_cursor"] and json_result["next_cursor"] > 0 
    cursor = json_result["next_cursor"]
    puts "Downloading the next page of lists..."
  else
    # Downloaded all the lists!
    break
  end
  
  # Only download 7 pages of lists (140 lists total) to prevent overflowing the
  # Twitter rate limit
  if requests_remaining <= 143
    puts "Stopping at 7 pages of lists to prevent overflowing the Twitter 150 request/hour rate limit."
    break
  end
end
membership_lists.flatten!


json_user_list = Hash.new # List of all users on all lists
json_user_count_list = Hash.new # List of reference counts for each user
  
# Download the complete membership of every list that includes our user
json_user_lists = Array.new
current_list = 1
list_count = membership_lists.size
puts "User is referenced on #{list_count} lists"

membership_lists.each do |list|
  # Download list
  begin
    puts "Downloading list #{current_list}/#{list_count}"
    current_list += 1
    result_list = Net::HTTP.get( URI( "http://api.twitter.com/1/lists/members.json?list_id=#{list['id']}" ) )
  rescue
    puts "Error downloading Twitter list. Skipping"
    next
  end
  
  begin
    json_list = JSON.parse( result_list )  
  rescue
    puts "Error parsing JSON. Skipping"
    next
  end  
  
  puts json_list["error"] if json_list["error"]
    
  # Add each user to the user list, increment counts
  json_list["users"].each do |user|
    user_id = user["id"]    
    json_user_list[ user_id ] = user unless json_user_list.has_key?( user_id )
    
    if json_user_count_list.has_key?( user["id"] )
      json_user_count_list[ user["id"] ] = json_user_count_list[ user["id"] ] + 1
    else
      json_user_count_list[ user["id"] ] = 0
    end
  end if json_list["users"]    

  # Break if we hit the Twitter rate limit
  if current_list > ( requests_remaining - 1 )
    puts "Breaking to avoid the Twitter rate limit"
    break
  end      
end


puts "Total Users on all lists: #{json_user_list.size}"
puts "\n\n\n"
puts "***All users listed at least twice on matching Twitter lists:***"

json_user_count_list.keys.each do |count_key|
  if json_user_count_list[ count_key ] >= 2
    
    user_json = json_user_list[ count_key ]
    
    # Skip source user
    next if user_json["screen_name"] == source_screen_name    
    
    # Print out all users
    begin
      puts user_json["screen_name"]
      puts "#{json_user_count_list[ count_key ]} references"    
      puts user_json["name"]
      puts user_json["status"]["text"]
      puts "#{user_json["followers_count"]} followers"
      puts "\n\n\n"
    rescue
      puts "Error parsing user\n\n\n"
    end
  end
end