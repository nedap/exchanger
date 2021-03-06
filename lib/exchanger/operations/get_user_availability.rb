module Exchanger
  # Getting User Availability
  # 
  # http://msdn.microsoft.com/en-us/library/aa494212(v=exchg.80)
  class GetUserAvailability < Operation
    FREE = 0
    TENTATIVE = 1
    BUSY = 2
    OUT_OF_OFFICE = 3
    NO_DATA = 4
    
    class Request < Operation::Request
      attr_accessor :time_zone, :email_address, :start_time, :end_time, :merged_free_busy_interval_in_minutes

      # Reset request options to defaults.
      def reset
        @time_zone = 'Europe/London'
        @email_address = 'test.test@test.com'
        @start_time = Date.today.to_time + 1
        @end_time = (Date.today + 1).to_time - 1
        @merged_free_busy_interval_in_minutes = 60
      end

      def time_zone_period
        begin
          current_tz = TZInfo::Timezone.get(time_zone).current_period
        rescue => e
          raise Exchanger::Operation::ResponseError.new(e, 500)
        end
      end

      def to_xml
        current_tz = time_zone_period
        minutes_of_utc_offset = current_tz.utc_offset/60 # Get the base offset of the timezone from UTC in minutes
        minutes_of_std_offset = current_tz.std_offset/60 # Get the daylight savings offset from standard time in minutes

        start_date_time = start_time.strftime("%Y-%m-%dT%H:%M:%S")
        end_date_time = end_time.strftime("%Y-%m-%dT%H:%M:%S")

        Nokogiri::XML::Builder.new do |xml|
           xml.send("soap:Envelope", "xmlns:xsi" => NS["xsi"], "xmlns:xsd" => NS["xsd"], "xmlns:soap" => NS["soap"], "xmlns:t" => NS["t"], "xmlns:m" => NS["m"]) do
             xml.send("soap:Body") do
               xml.send("m:GetUserAvailabilityRequest") do
                 xml.send("t:TimeZone") do
                   xml.send("t:Bias", (minutes_of_utc_offset * -1))
                   # if daylight savings time is active for current time zone
                   # How to find correct standard time and daylight saving time configuration
                   if current_tz.dst?
                     xml.send("t:StandardTime") do
                       xml.send("t:Bias", 0)
                       xml.send("t:Time", "04:00:00")
                       xml.send("t:DayOrder", 5)
                       xml.send("t:Month", 10)
                       xml.send("t:DayOfWeek", "Sunday")
                     end
                     xml.send("t:DaylightTime") do
                       xml.send("t:Bias", (minutes_of_std_offset * -1))
                       xml.send("t:Time", "03:00:00")
                       xml.send("t:DayOrder", 5)
                       xml.send("t:Month", 3)
                       xml.send("t:DayOfWeek", "Sunday")
                     end
                   end
                 end
                 xml.send("m:MailboxDataArray") do
                   xml.send("t:MailboxData") do
                     xml.send("t:Email") do
                       xml.send("t:Address", email_address)
                     end
                     xml.send("t:AttendeeType", "Required")
                     xml.send("t:ExcludeConflicts", "false")
                   end
                 end
                 xml.send("t:FreeBusyViewOptions") do
                   xml.send("t:TimeWindow") do
                     xml.send("t:StartTime", start_date_time)
                     xml.send("t:EndTime", end_date_time)
                   end
                   xml.send("t:MergedFreeBusyIntervalInMinutes", merged_free_busy_interval_in_minutes)
                   xml.send("t:RequestedView", "DetailedMerged")
                 end
               end
             end
           end
         end
      end
    end

    class Response < Operation::Response
      def merged_free_busy
        to_xml.xpath(".//t:MergedFreeBusy", NS).text.split("").map do |code|
          case code
          when "0"
            GetUserAvailability::FREE
          when "1"
            GetUserAvailability::TENTATIVE
          when "2"
            GetUserAvailability::BUSY
          when "3"
            GetUserAvailability::OUT_OF_OFFICE
          when "4"
            GetUserAvailability::NO_DATA
          end
        end
      end
    
      def items
        to_xml.xpath(".//t:CalendarEventArray", NS).children.map do |node|
          item_klass = Exchanger.const_get(node.name)
          item_klass.new_from_xml(node)
        end
      end
    end
  end

end
