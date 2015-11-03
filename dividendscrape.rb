#!/usr/bin/env ruby
require 'net/http'
require 'optparse'
require 'pry'
require 'nokogiri'
require 'thread/pool'

@options = {}
args = OptionParser.new do |opts|
  opts.banner = "Dividendscrape.rb VERSION: 1.0.0 - UPDATED: 10/19/2015\r\n\r\n"
  opts.banner += "Usage: dividendscrape [options]\r\n\r\n"
  opts.banner += "\texample: ./dividendscrape -s \"PG\"\r\n\r\n"
  opts.on("-s", "--stock [Stock Symbol]", "The ticker symbold for a single stock") { |stock| @options[:stock] = stock }
  opts.on("-S", "--stock-list [Stock File]", "File containing a list of stock symbols") { |stocks| @options[:stocks] = File.open(stocks, "r").read }
  opts.on("-v", "--verbose", "Enables verbose output\r\n\r\n") { |v| @options[:verbose] = true }
end
args.parse!(ARGV)

def get_dividend_info(symbol)
	begin
		stock_uri = URI.parse(get_url(symbol))
		stock_response_page = Net::HTTP.get_response(stock_uri)
		parseable = Nokogiri::HTML(stock_response_page.body)
		if results = parse_results(parseable, symbol)
			output = ""
			results.each { |k, v| output << v.chomp + "\t" }
			puts output
		end
	rescue URI::InvalidURIError => uri_error
		puts "Could not find Dividend information for: #{symbol}" if @options[:verbose]
		return
	end
end

def get_url(symbol)
	search_uri = URI.parse("http://www.dividend.com/search/?q=" + symbol.chomp)
	response = Net::HTTP.get_response(search_uri)
	return response.code == "302" ? response['location'] : nil
end

def parse_results(page, symbol)
	stock = {}
	stock[:ticker] = page.css('.data-title__symbol').text
	return nil if stock[:ticker] == ""
	stock[:company] = page.css('.data-title__name').text
	stock[:sector] = page.css('.breadcrumb').css('a')[2] ? page.css('.breadcrumb').css('a')[2].text : "Uncategorized"
	stock[:industry] = page.css('.category').text
	stock[:price] = page.css('.price').text
	stock[:eps] = page.css('.payout_ratio').css('.supplemental').text.split(' ')[1]
	stock[:dividend] = page.css('.dividend-per-share').css('.value').text
	return nil if stock[:dividend] == "$0.00"
	stock[:yield] = calculate_yield(stock[:dividend], stock[:price])
	stock[:payout_ratio] = page.css('.payout_ratio').css('.value').text
	stock[:dividend_years] = page.css('.increasing-dividend-period').css('.value').text.split(' ')[0]
	payout_table = page.xpath('//table[@class="base-table not-clickable payout-data"]//tr').collect
	stock[:three_year_growth] = calculate_dividend_growth_rate(payout_table, 3, symbol)
	stock[:five_year_growth] = calculate_dividend_growth_rate(payout_table, 5, symbol)
	stock[:ten_year_growth] = calculate_dividend_growth_rate(payout_table, 10, symbol)
	return stock
end

def calculate_yield(dividend, price)
	p1 = price.gsub(/\$/,'').to_f
	d1 = dividend.gsub(/\$/,'').to_f
	return ((d1/p1) * 100).round(2).to_s + "%"
end

def calculate_dividend_growth_rate(table, periods, symbol)
	payouts = Array.new
	begin
		table.each { |payout|  
			payout = payout.xpath('td[1]').text.gsub(/\$/,'').to_f.round(2)
			payouts << payout unless (payout == 0.0 || payout > 1.99)
		}
		period = payouts.uniq[0..(periods-1)]
		growth = ((period[0] / period[-1]) - 1).round(2)
	rescue NoMethodError => calc_error
		return nil
	end
	return growth.to_s
end

if @options[:stock]
	get_dividend_info(@options[:stock])
	exit!
elsif @options[:stocks]
	@options[:stocks].each_line { |stock| get_dividend_info(stock) }
	exit!
end