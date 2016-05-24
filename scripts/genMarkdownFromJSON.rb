###
# This program reads the JSON specification files and creates the Markdown files (minus the examples). 
# Location: https://github.com/sumurthy/Js-Spec-Gen
###
require 'pathname'
require 'json'
require 'FileUtils'
require 'base64'

module SpecMaker

	# Initialize 
	NEWLINE = "\n"
	JSON_SOURCE_FOLDER = "jsonFiles/source"		
	ENUMS = 'jsonFiles/settings/enums.json'
	MARKDOWN_OUTPUT_FOLDER = "../markdown/"
	WRITE_BACK = %w[# | * _ ]
	TAKE_ACTION = %w[%]
	TAKE_REPEAT_ACTION = %w[>]
	MARK_REGION = %w[<]
	IGNORE = %w[/]

	EXAMPLES_FOLDER = "../api-examples-to-merge/"

	SIMPLETYPES = %w[int string date object object[][] double bool flaot number void object[]]

	# Read config and json_struct files 

	CONFIG = "../config/config.json"
	@config = JSON.parse(File.read(CONFIG, :encoding => 'UTF-8'), {:symbolize_names => true})
	puts "....Starting run for the app #{@config[:app]}"
	puts
	## 
	# Load the output template 
	###
	@md_main = []
	@md_method = []
	@mdo = []
	@all_types = []
	@jsonHash = {}
	@region = 'object'
	@skip = false

	begin
		@md_main = File.readlines(@config[:mdTemplateMain])
	rescue => err
		abort("*** FATAL ERROR *** Input MD template file: #{@config[:mdTemplateMain]} doesn't exist. Correct and re-run." )
	end

	begin
		@md_method = File.readlines(@config[:mdTemplateMethod])
	rescue => err
		abort("*** FATAL ERROR *** Input MD template file: #{@config[:mdTemplateMethod]} doesn't exist. Correct and re-run." )
	end

	# Create markdown folder if it doesn't already exist
	Dir.mkdir(MARKDOWN_OUTPUT_FOLDER) unless File.exists?(MARKDOWN_OUTPUT_FOLDER)	

	# Clean-up the markdown folder
	FileUtils.rm Dir.glob(MARKDOWN_OUTPUT_FOLDER + '/*')

	if !File.exists?(JSON_SOURCE_FOLDER)
		abort("*** FATAL ERROR *** Input JSON resource folder: #{JSON_SOURCE_FOLDER} doesn't exist. Correct and re-run." )
	end

	if !File.exists?(EXAMPLES_FOLDER)
		puts "API examples folder does not exist"
	end	

	def self.decode(desc="")
		return Base64.decode64(desc).split('|').join(" 	 \n")
	end	

	def self.deep_copy(o)
		Marshal.load(Marshal.dump(o))
	end

	def self.hyperlink
	end

	def self.substitute(line="")	

		(line.sub! '%resourcename%', @jsonHash[:name]) if line.include?('%resourcename%')
		(line.sub! '%resourcedescription%', @jsonHash[:description]) if line.include?('%resourcedescription%')
		(line.sub! '%longobjectdescription%', (decode @jsonHash[:longDesc])) if line.include?('%longobjectdescription%')
		(line.sub! '%resourcenamespace%', @jsonHash[:namespace]) if line.include?('%resourcenamespace%')		
		(line.sub! '%minreqset%', @jsonHash[:reqSet].join(', ')) if line.include?('%minreqset%')
		(line.sub! '%minpermission%', @jsonHash[:minPermission]) if line.include?('%minpermission%')
		(line.sub! '%modes%', @jsonHash[:modes].join(', ')) if line.include?('%modes%')
		return line
	end

	def self.decorate_href (text='', addr='')

	end
	
	def self.get_type_link (type='')
		if @all_types.include? type.chomp('[]').downcase
			return '[' + type + '](' + type.chomp('[]').downcase + '.md' + ')'
		else
			return type
		end
	end

	def self.get_type_link_array (types=[])

		puts types
		text = ''
		types.each  do |type|
			text = text + (get_type_link type) + ' or '
		end
		puts ">> #{text}"
		return text.chomp(' or ')
	end

	def self.process_params
	end

	def self.process_properties(val='')
		val = val[1..-1]

		if @jsonHash[:properties]
			propreties = @jsonHash[:properties].sort_by { |v| v[:name] }
		end

		propreties.each do |prop|
			line = deep_copy(val)			
			line.sub! '%name%', prop[:name]
			line.sub! '%type%', (get_type_link_array prop[:dataType])
			line.sub! '%description%', prop[:description]
			if prop[:isReadonly]
				line.sub! '%nullable%', ' This property is read-only.'
			else
				line.sub! '%nullable%', ''
			end
			if prop[:isNullable]
				line.sub! '%nullable%', ' This property can contain null.'
			else
				line.sub! '%nullable%', ''
			end			
			line.sub! '%req%', prop[:reqSet].join
			@mdo.push line + '  ' + NEWLINE
		end

	end

	def self.process_enums(val='')

	end

	def self.process_methods(val='')

		val = val[1..-1]

		if @jsonHash[:methods]
			methods = @jsonHash[:methods].sort_by { |v| v[:name] }
		end

		methods.each do |method|
			line = deep_copy(val)			
			line.sub! '%name%', method[:name]
			line.sub! '%type%', (get_type_link_array method[:returnType])
			line.sub! '%description%', method[:description]
			if method[:returnNullable]
				line.sub! '%nullable%', ' This method can return null.'
			else
				line.sub! '%nullable%', ''
			end	
			line.sub! '%req%', method[:reqSet].join
			line.sub! '%link%', method[:name].downcase

			@mdo.push line + '  ' + NEWLINE
		end		

	end

	def self.process_method_details(val='')

	end

	def self.direct(key='', key2= '', val='')

		case key 
		when '%'
			val = substitute val
			return val
		when '>'
			case @region
			when 'properties'
				process_properties val
			when 'methods'
				process_methods val
			when 'parameters'
				process_params val
			when 'enums'
				process_enums val
			end
		end
		return
	end

	def self.set_region(val='')

		if val.include?('</')
			@region = 'none'
			return
		else
			#remove characters < / and >
			@region = val.tr('</>', '')
		end

		if @jsonHash[@region.to_sym] && @jsonHash[@region.to_sym].length > 0 
			@skip = false
		else
			@skip = true
		end
		@skip = false if @region == 'resource'

		return 
	end

	# Conversion to specification 
	def self.convert_to_spec (item=nil)
		@jsonHash = JSON.parse(item, {:symbolize_names => true})

		# Obtain the resource name. Read the examples file, if it exists. 
		@resource = @jsonHash[:name]
		
		# example_lines = ''
		# @exampleFileFound = false
		# begin
		# 	#example_lines = File.readlines(File.join(JSON_EXAMPLE_FOLDER + @resource.downcase + ".md"))
		# 	example_lines = File.readlines(EXAMPLES_FOLDER + @resource.downcase + ".md")
		# 	@gsType = determine_getter_setter_type example_lines
		# 	@exampleFileFound = true
		# rescue => err
		# 	puts "....Example File does not exist for: #{@resource}"
		# end

		@md_main.each_with_index do |tline, i|


			key = tline.to_s[0]
			key2 = tline.to_s[0..1]
			key = '*' if key.strip.length == 0
			val = tline.strip

			set_region val if MARK_REGION.include? key	
						
			next if @skip

			hasVar = val.include?('%') ? true  : false

			case key 
			when *WRITE_BACK
				val = substitute(val) if hasVar
				@mdo.push val + NEWLINE
				next
			when *TAKE_ACTION
				@mdo.push (direct(key, key2, val) + NEWLINE)
				next
			when *TAKE_REPEAT_ACTION
				direct(key, key2, val)
				next
			when *IGNORE
				next
			else
				next
			end

		end

	end

	# Main loop. 
	processed_files = 0

	Dir.foreach(JSON_SOURCE_FOLDER) do |item|
		next if item == '.' or item == '..'
		@all_types.push item.chomp('.json')
	end

	puts @all_types

	Dir.foreach(JSON_SOURCE_FOLDER) do |item|
		next if item == '.' or item == '..'
		fullpath = JSON_SOURCE_FOLDER + '/' + item.downcase

		if File.file?(fullpath)
			puts "*-> Processing #{item}"
			convert_to_spec File.read(fullpath)
		end

		outfile = MARKDOWN_OUTPUT_FOLDER + item.chomp('.json') + '.md'

		file=File.new(outfile,'w')
		@mdo.each do |line|
			file.write line
		end
		@mdo = []
		processed_files = processed_files + 1

	end
	puts ""
	puts "*** OK. Processed #{processed_files} input files. ***"
end
