module 'Vis', ->
    class @DataPicker extends Backbone.View
        template: Handlebars.compile $('#data_picker-template').html()

        class: 'data-picker'

        events: =>
            'click .nav li': 'switch_filter'

        # The DataPicker takes the following arguments:
        #   data_streams: a list of DataStreams to update whenever new data is picked
        initialize: (data_streams)->
            @filters = {}
            @collections = [namespaces, datacenters, machines]

            @color_scheme = d3.scale.category20()
            @color_map = new ColorMap()
            for collection in @collections
                collection.map (model, i) =>
                    @color_map.set(model.get('id'), @color_scheme i)

            # Create one filter for each type of data (machine, namespace, datacenter, etc.) we use in all of these data streams
            for collection in @collections
                @filters[collection.name] = new Vis.DataStreamFilter collection, data_streams, @color_map
            @selected_filter = @filters[@collections[0].name]

        render: =>
            # Recreate color data whenever the picker is shown. | Ideally this should be removed when datastreams are cleaned up and loaded from the server TODO
            for collection in @collections
                collection.map (model, i) =>
                    @color_map.set(model.get('id'), @color_scheme i)

            @.$el.html @template
                stream_filters: _.map(@filters, (filter, collection_name) =>
                    name: collection_name
                    selected: filter is @selected_filter
                )

            @.$('.filter').html @selected_filter.render().el

            @.delegateEvents()
            return @

        switch_filter: (event) =>
            collection_name = $(event.currentTarget).data('filter')
            @selected_filter = @filters[collection_name]

            @render()

            event.preventDefault()

        get_color_map: => @color_map

    class @DataStreamFilter extends Backbone.View
        className: 'data-stream-filter'
        template: Handlebars.compile $('#data_stream_filter-template').html()

        events: ->
            'click .model': 'select_model'

        # The DataStreamFilter takes the following arguments:
        #   collection: the collection whose models will be used for this filter
        #   data_streams: data streams to update whenever a new set of models is selected
        initialize: (collection, data_streams, color_map) ->
            @collection = collection
            @data_streams = data_streams
            @color_map = color_map

            @models_selected = {}
            for model in collection.models
                @models_selected[model.get('id')] = true

        render: =>
            @.$el.html @template
                models: _.map(@collection.models, (model) =>
                    id: model.get('id')
                    name: model.get('name')
                    selected: @models_selected[model.get('id')]
                    color: @color_map.get(model.get('id'))
                )

            @filter_data_sources()

            @.delegateEvents()
            return @

        select_model: (event) =>
            $model = @.$(event.currentTarget)
            id = $model.data('id')
            @models_selected[id] = not @models_selected[id]
            $('input', $model).attr('checked', @models_selected[id])

            @filter_data_sources()

        filter_data_sources: =>
            active_uuids = []
            _.each @models_selected, (selected, uuid) -> active_uuids.push uuid if selected

            for stream in @data_streams
                stream.set
                    'active_uuids': active_uuids

    class @ResourcePieChart extends Backbone.View
        className: 'resource-pie-chart'
        no_data_template: Handlebars.compile $('#vis_no_data-template').html()
        empty_chart_showing: false

        events: ->
            'click': 'update_chart'

        initialize: (data_stream, color_map) ->
            log_initial '(initializing) resource pie chart'

            # Use the given datastream to back the pie chart
            @data_stream = data_stream

            # Use a pre-defined color scale to pick the colors
            @color_map = color_map

            # Dimensions of the pie chart
            @width = 220
            @height = 200
            @radius = Math.floor(Math.min(@width, @height) / 2  * 0.65)
            @text_offset = 10

            # Transition duration (update frequency) in ms
            @duration = 1000

            # Function to sort the data in order of ascending names (a and b are two datapoints to be compared to one another)
            sort_data_points = (a, b)->
                name = (data_point) -> data_point.collection.get(data_point.id).get('name')
                return d3.ascending(name a, name b)

            # Use the pie layout, indicate where to get the actual value from and how to sort the data
            @donut = d3.layout.pie().sort(sort_data_points).value((d) -> d.value)
            # Define the arc's width using the built-in arc function
            @arc = d3.svg.arc().innerRadius(@radius).outerRadius(@radius - 25)

            # Make the data change every few ms | faked TODO
            setInterval @update_chart, 2000

        # Utility function to get the total value of the data points based on filtering
        #   data: data set that contains data points to be totaled
        get_total: (data) =>
            # Choose only data points that are among the selected sets, get their sum
            values = _.map data, (data_point) -> data_point.value
            return _.reduce values, (memo, num) -> memo + num

        # Utility function to only get a filtered subset of the data
        get_filtered_data: =>
            return _.map @data_stream.get('active_uuids'), (uuid) =>
                @data_stream.get('data').get(uuid).toJSON()

        render: =>
            # We'll be recreating $el from scratch each time
            @.$el.empty()

            @data_stream.off 'change:active_uuids', @draw_pie_chart
            @data_stream.on 'change:active_uuids', @draw_pie_chart

            @draw_pie_chart_layout()

            return @

        # Draw the pie chart layout from scratch (on first run)
        draw_pie_chart_layout: =>
            # Define the base visualization layer for the pie chart
            svg = d3.select(@el).append('svg:svg')
                    .attr('width', @width)
                    .attr('height', @height)
            @svg = svg

            @groups = {}

            # Group for the pie sections, ticks, and labels
            @groups.arcs = svg.append('svg:g')
                .attr('class', 'arcs')
                .attr('transform', "translate(#{@width/2},#{@height/2})")

            # Group for text in the center
            @groups.center = svg.append('svg:g')
                .attr('class', 'center')
                .attr('transform', "translate(#{@width/2},#{@height/2})")

            # Add the center text
            #   label for just the "total" element
            @groups.center.append('svg:text')
                .attr('class','total-label')
                .attr('dy', -10)
                .attr('text-anchor', 'middle')
                .text('Total')
            #   label for the units
            @groups.center.append('svg:text')
                .attr('class','total-units')
                .attr('dy', 21)
                .attr('text-anchor', 'middle')
                .text('mb')
            #   label for the actual value
            @groups.center.append('svg:text')
                .attr('class','total-value')
                .attr('dy', 7)
                .attr('text-anchor', 'middle')

            @draw_pie_chart()

        # Draw the pie chart using a new dataset
        draw_pie_chart: =>
            # Get the selected datasets. If there aren't any selected, indicate no data was selected.
            filtered_data = @get_filtered_data()

            if filtered_data.length is 0
                @show_empty_chart()
                return
            else
                @hide_empty_chart() if @empty_chart_showing

            # Calculate a new total
            total = @get_total filtered_data

            # Update the pie chart with the new data
            @arcs = @groups.arcs.selectAll('g.arc').data(@donut(filtered_data), (d) -> d.data.id)

            # Stop all running animations / tweenings to allow us to redraw the pie chart.
            d3.selectAll("*").transition().delay(0)

            # Whenever a datum is entered, create a new group that will contain the arc path, arc tick, and arc label
            entering_arc_groups = @arcs
                .enter()
                    .append('svg:g')
                        .attr('class','arc')

            # Make sure each arc path has positional data to help tween: if it's missing, use the current position
            @arcs.each((d) =>
                # Make sure we have a color
                if not @color_map.get(d.data.id)?
                    console.log "No color can be found for #{d.data.id}."
                # Save the current state of the arc (angles, values, etc.) for use when tweening
                d.data.previous =
                    endAngle: d.endAngle
                    startAngle: d.startAngle
                    value: d.value
            )

            # Add an arc path to the group
            entering_arc_groups.append('svg:path')
                .attr('class','section')
                # Fill the pie chart with the color scheme we defined
                .attr('fill', (d) => @color_map.get(d.data.id))

            # Add a tick to the group
            entering_arc_groups.append('svg:line')
                    .attr('class','tick')
                    .attr('x1', 0)
                    .attr('x2', 0)
                    .attr('y1', -@radius - 7)
                    .attr('y2', -@radius - 3)

            # Add a label to each group
            entering_arc_groups.append('svg:text')
                .attr('class','label')
                .attr('text-anchor','middle')
                .attr('dominant-baseline','central')


            # Update the center text
            @groups.center.select('text.total-value').text(total)

            # Whenever a datum is exited, just remove the group
            @arcs.exit().remove()
            
            # Calculate the positions, transformations, and data for each of the arc group elements
            @arcs.select('path.section').attr('d', @arc)
            @arcs.select('line.tick').attr('transform', (d) -> "rotate(#{(d.startAngle + d.endAngle)/2 * (180/Math.PI)})")

            # Terrible hack that works: set a timeout of zero so that this is called only when the rendered view is actually added to the DOM
            # Reason this is necessary: getting the bounding box of the text node (bbox) will only work when the text box is actually rendered on the page
            setTimeout =>
                # Keep a local reference to the class function
                pie_label_position = @pie_label_position
                @arcs.select('text.label')
                    .text((d) =>
                        percentage = (d.value/total) * 100
                        return percentage.toFixed(1) + '%'
                    )
                    # Determine each pie label's position
                    .attr('transform', (d) ->
                        angle = (d.startAngle + d.endAngle)/2
                        pos = pie_label_position(this, angle)
                        return "translate(#{pos.x},#{pos.y})"
                    )
            , 0

        update_chart: =>
            # Get the selected datasets. If there aren't any selected, indicate no data was selected.
            filtered_data = @get_filtered_data()
            if @empty_chart_showing or filtered_data.length is 0
                return

            # Save positional data calculated by the previous tween before we fetch new data
            existing_positional_data = {}
            for datum in @arcs.data()
                if datum.data.previous?
                    existing_positional_data[datum.data.id] = datum.data.previous

            # Run the updated data through the donut layout manager
            new_data = @donut filtered_data

            # Drop in positional data if it exists for the given arc
            new_data = _.map new_data, (datum) ->
                if datum.data.id of existing_positional_data
                    datum.data.previous = existing_positional_data[datum.data.id]
                return datum

            # Calculate a new total
            total = @get_total new_data

            # Update the pie chart with the new data
            @arcs.data(new_data, (d) -> d.data.id)

            # Use an arc tweening function to transition between arcs
            @arcs.select('path.section').transition().duration(@duration)
                .attrTween('d', (d) =>
                    # Interpolate from the previous angle to the new angle
                    i = d3.interpolate d.data.previous, d

                    # Return a function that specifies the new path data using the interpolated values
                    return (t) => @arc(i(t))
                )
                .each 'end', (d) ->
                    d.data.previous =
                        endAngle: d.endAngle
                        startAngle: d.startAngle
                        value: d.value

            # Transition between ticks
            @arcs.select('line.tick').transition().duration(@duration)
                .attrTween('transform', (d) =>
                    # Convert the previous tick angle and new tick angle, converting radians to degrees
                    previous_angle = (d.data.previous.startAngle + d.data.previous.endAngle)/2 * (180/Math.PI)
                    new_angle =  (d.startAngle + d.endAngle)/2 * (180/Math.PI)

                    # Interpolate from the previous angle to the new angle
                    i = @interpolate_degrees previous_angle, new_angle

                    # Return a string indicating the SVG translation for the tick at each point along the interpolation
                    return (t) => "rotate(#{i(t)})"
                )

            # Keep a local reference to the class function
            pie_label_position = @pie_label_position
            # Transition between label positions
            pie_labels = @arcs.select('text.label')
                .transition().duration(@duration)
                    .attrTween('transform', (d) ->
                            previous_angle = (d.data.previous.startAngle + d.data.previous.endAngle)/2
                            new_angle = (d.startAngle + d.endAngle)/2
                            i = d3.interpolate previous_angle, new_angle
                            return (t) =>
                                p = pie_label_position(this, i(t))
                                return "translate(#{p.x},#{p.y})"
                    )
                    .text((d) =>
                        percentage = (d.value/total) * 100
                        return percentage.toFixed(1) + '%'
                )

            # Update the tracked value
            @groups.center.select('text.total-value')
                .text(total)

        # Show the empty chart div, hide the svg
        show_empty_chart: =>
            @.$el.append @no_data_template()
            @.$('svg').hide()
            @empty_chart_showing = true

        # Hide the empty chart div, show the svg
        hide_empty_chart: =>
            $('.no-data').remove()
            @.$('svg').show()
            @empty_chart_showing = false

        # Calculates the x and y position for labels on each section of the pie chart
        # Takes a text box that will be used as the label, and an angle that the label should be positioned at
        pie_label_position: (text_box, angle) =>
            # Bounding box of the text label
            bbox = text_box.getBBox()
            # Distance the text box should be from the circle
            r = @radius + @text_offset

            # Point at which the vector from the center of the pie chart intersects with the ellipse of the text box
            intersection =
                x: r * Math.sin(angle)
                y: -r * Math.cos(angle)
            # Point where the center of the rect should be placed
            center_ellipse =
                x: intersection.x + bbox.width/2 * Math.sin(angle)
                y: intersection.y - bbox.height/2 * Math.cos(angle)
            # Return the SVG point to draw the rect from
            return p =
                x: center_ellipse.x
                y: center_ellipse.y


        # Returns an interpolator for angles (designed to move within [-180,180])
        interpolate_degrees: (start_angle, end_angle) ->
            delta = end_angle - start_angle
            delta -= 360 while delta >= 180
            delta += 360 while delta < -180

            return d3.interpolate start_angle, start_angle + delta

    class @ClusterPerformanceGraph extends Backbone.View
        className: 'cluster-performance-graph'
        loading_template: Handlebars.compile $('#vis_loading-template').html()
        no_data_template: Handlebars.compile $('#vis_no_data-template').html()
        stream_picker_template: Handlebars.compile $('#vis-graph_stream_picker-template').html()
        empty_chart_showing: false

        events: ->
            'click .stream-picker .datastream': 'change_data_stream'

        time_now: -> new Date(Date.now() - @duration)

        get_data: =>
            # Create a zero-filled array the size of the first data set's cached values: this array will help keep track of stacking data sets
            previous_values = _.map @data_stream.get('cached_data')[@active_uuids[0]], -> 0

            _.map @active_uuids, (uuid) =>
                active_data = @data_stream.get('cached_data')[uuid]
                points = _.map active_data, (data_point,i) -> _.extend data_point.toJSON(),
                    previous_value: previous_values[i]
                
                # The current active dataset values should be added to previous_values: this helps stack each dataset on top of one another
                active_values = _.map active_data, (datapoint) -> datapoint.get('value')
                previous_values = _.map _.zip(active_values, previous_values), (zipped) ->
                    _.reduce zipped, (t,s) -> t + s

                return {
                    uuid: uuid
                    datapoints: _.rest points, Math.max(0, points.length - @n) # Only < n points should be plotted
                }

        get_latest_time: (data) ->
            last_times = _.map data, (data_set) -> data_set.datapoints[data_set.datapoints.length-1].time
            return _.min last_times

        get_highest_value: (data) ->
            # Get an array of arrays for the values of each data set. Example: [[1,2],[3,4],[5,6]]
            active_values = _.map data, (data_set) ->
                _.map data_set.datapoints, (datum) -> return datum.value

            if active_values.length is 0
                return 0
            # Get an array that has just the sum of values in each position (peaks). Example: [9,12]
            sum_values = _.reduce active_values, (prev_values, values) -> # Reduce to one array
                _.map _.zip(prev_values, values), (zipped) -> # Sum each arrays' elements
                    _.reduce zipped, (t,s) -> t + s

            # Return the maximum value (highest peak of data)
            return d3.max(sum_values)
            
        initialize: (data_streams, color_map) ->
            log_initial '(initializing) cluster performance graph'
            # Generate fake data for visualization reasons | faked data TODO
            # Number of elements
            @n = 50
            # Transition duration (update frequency) in ms
            @duration = 1500

            # Data stream that backs this plot, and the currently active uuids
            @data_streams = data_streams
            @data_stream = data_streams[0]
            @active_uuids = @data_stream.get('active_uuids')

            # Use a pre-defined color scale to pick the colors
            @color_map = color_map

            # Dimensions and margins for the plot
            @margin =
                top: 6
                right: 0
                bottom: 40
                left: 40
            @width = 600 - @margin.right
            @height = 300 - @margin.top - @margin.bottom

        render: =>
            # We'll be recreating $el from scratch each time
            @.$el.empty()

            # Remove all previous bindings on the datastreams we're watching
            for stream in @data_streams
                stream.off  'cache_ready', @cache_ready
                stream.off 'change:active_uuids', @active_uuids_changed

            # Get the new set of active datasets
            @active_uuids = @data_stream.get('active_uuids')
            
            # Draw the chart immediately if enough data has been cached
            if @active_uuids.length > 0 and @get_data()[0].datapoints.length >= 2
                @draw_chart()
            else if @active_uuids.length is 0
                @show_empty_chart()
            # Otherwise, set up a binding to draw the chart when the cache is ready
            else
                @data_stream.on 'cache_ready', @cache_ready
                @.$el.html @loading_template()

            # Bind to datapicker changes
            @data_stream.on 'change:active_uuids', @active_uuids_changed

            # Reattach callbacks
            @.delegateEvents()
                
            return @

        # Draw the chart when the cache is ready
        cache_ready: =>
            @.$('.loading').fadeOut 'medium', =>
                $(@).remove()
                @draw_chart()

        # Update the new set of active datasets
        active_uuids_changed: =>
            @active_uuids = @data_stream.get('active_uuids')
            @draw_chart()

        # Set up datastream picker
        add_data_stream_picker: =>
            # Remove a stream picker if it already exists
            @.$('.stream-picker').remove()

            # If there is more than one data stream being used, add a stream picker 
            if @data_streams.length > 1
                @.$el.append @stream_picker_template
                    datastreams: _.map(@data_streams, (data_stream, i) =>
                        id: i
                        name: data_stream.get('pretty_print_name')
                        selected: @data_stream is data_stream
                    )

        change_data_stream: (event) =>
            # Remove the binding that watches @data_stream for changes in active uuids
            @data_stream.off 'change:active_uuids'
            
            # Update the @data_stream reference based on what was clicked (and make appropriate visual changes to the radio buttons)
            $data_stream = @.$(event.currentTarget)
            id = $data_stream.data('id')
            @data_stream = @data_streams[id]
            @.$('.stream_picker input').attr('checked', false)
            $('input', $data_stream).attr('checked', true)
            
            # Now that we've updated the @data_stream reference, bind again to datapicker changes
            @data_stream.on 'change:active_uuids', @active_uuids_changed

            @draw_chart()

        draw_chart: =>
            data = @get_data()

            # Stop all running animations / tweenings to allow us to redraw the line chart
            d3.selectAll("*").transition().delay(0)

            # Add a data stream picker if it's needed (if there is more than one data stream for this graph)
            @add_data_stream_picker()

            @.$('svg').remove()

            # If there is no data, don't render the chart
            if data.length is 0
                @show_empty_chart()
                return
            else
                @hide_empty_chart() if @empty_chart_showing

            # Get the latest recorded time
            last_time = @get_latest_time data

            # The x scale's domain defines a window of 30 seconds, accounting for the points we're buffering
            @x = d3.time.scale()
                .domain([last_time - 30000 - 2 * @duration, last_time - 2 * @duration])
                .range([0, @width])

            # The y scale should start at zero, and end at the highest sum across all data sets
            @y = d3.scale.linear()
                .domain([0, @get_highest_value(data)])
                .range([@height, 0])

            # Define the axes
            @x_axis = => d3.svg.axis().scale(@x).orient('bottom').ticks(5).tickFormat(d3.time.format('%X'))
            @y_axis = => d3.svg.axis().scale(@y).ticks(5).orient('left')

            # Define the lines for each data set
            @line = d3.svg.line()
                .interpolate('linear')
                .x((d,i) => @x(d.time)
                )
                .y((d) => @y(d.value + d.previous_value))

            # Define the fill for each data set
            @area = d3.svg.area()
                .x((d,i) => @x(d.time))
                .y0(@height-1)
                .y1((d) => @y(d.value + d.previous_value))

            @chart = {}

            # Define and add the base visualization layer for the plot
            @chart.svg = d3.select(@el).append('svg:svg')
                    .attr('width', @width + @margin.left + @margin.right)
                    .attr('height', @height + @margin.top + @margin.bottom)
                # Group that will hold all svg elements: translate it to accomodate internal margins
                .append('svg:g')
                    .attr('transform', "translate(#{@margin.left},#{@margin.top})")

            # Define the clipping path: we need to clip the line to make sure it doesn't interfere with the axes
            @chart.clipping_path = @chart.svg.append('defs').append('clipPath')
                    .attr('id', 'clip')
                .append('rect')
                    .attr('width', @width)
                    .attr('height', @height)

            # For each data set, create a group, add a clipping path, and set the data to be associated with the data set
            @chart.data_sets = {}
            # Add elements from the back, since SVG's z-order depends on the order in which elements are added
            for i in [data.length-1..0]
                data_set = data[i]
                color = @color_map.get(data_set.uuid)
                group = @chart.svg.append('g')
                        .attr('clip-path', 'url(#clip)')
                        .data([data_set.datapoints])

                # Add a line to each data set group
                group.append('path')
                        .attr('class','line')
                        .attr('stroke', color)
                        .attr('d', @line)

                # Add an area fill to each data set group
                group.append('path')
                        .attr('class','area')
                        .attr('fill', color)
                        .attr('d', @area)

                @chart.data_sets[data_set.uuid] = group

            # Define and add the axes
            @chart.axes =
                x: @chart.svg.append('g')
                    .attr('class', 'x-axis')
                    .attr('transform', "translate(0,#{@height})")
                    .call @x_axis()
                y: @chart.svg.append('g')
                    .attr('class', 'y-axis')
                    .call @y_axis()

            # Start the first tick
            @update_chart()

            return @

        # Update the chart (each tick)
        update_chart: =>
            data = @get_data()
            last_time = @get_latest_time data

            # Update the domains for both axes
            @x.domain([last_time - 30000 - @duration, last_time - @duration])

            # For the y-axis, the domain should only grow, not shrink, based on previous domains calculated
            existing_domain = @y.domain()
            highest_value = d3.max([@get_highest_value(data), existing_domain[1]])
            @y.domain([0, highest_value])

            animate = (data_set) =>
                group = @chart.data_sets[data_set.uuid]

                # Update the data for each data set
                group.data([data_set.datapoints])

                slide_path_to = @x(last_time - @duration) - @x(last_time)
                # Redraw and transition the line for each data set
                group.select('path.line')
                    # Redraw the line, but don't transform anything yet (otherwise the effect is visually jarring)
                    .attr('d', @line)
                    .attr('transform', null)
                    # Slide in the newly drawn line by translating it
                    .transition()
                        .duration(@duration)
                        .ease('linear')
                        .attr('transform', "translate(#{slide_path_to})")

                # Redraw and transition the area fill for each data set
                group.select('path.area')
                    .attr('d', @area)
                    .attr('transform', null)
                    .transition()
                        .duration(@duration)
                        .ease('linear')
                        .attr('transform', "translate(#{slide_path_to})")
            for data_set in data
                animate data_set

            # Transition the axes: slide linearly
            @chart.axes.x.transition()
               .duration(@duration)
               .ease('linear')
               .call(@x_axis())

            @chart.axes.y.transition()
                .duration(@duration)
                .ease('linear')
                .call(@y_axis())
                # Call the tick function again after this transition is finished (infinite loop)
                .each 'end', => @update_chart() if data_set.uuid is @active_uuids[@active_uuids.length - 1]

        # Show the empty chart div, hide the svg
        show_empty_chart: =>
            @.$el.append @no_data_template()
            @.$('svg').hide()
            @.$('.stream-picker').hide()
            @empty_chart_showing = true

        # Hide the empty chart div, show the svg
        hide_empty_chart: =>
            $('.no-data').remove()
            @.$('svg').show()
            @.$('.stream-picker').show()
            @empty_chart_showing = false