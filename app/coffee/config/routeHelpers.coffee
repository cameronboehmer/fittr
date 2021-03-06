# call backs for the routes

User    = require '../models/user'
Stats   = require '../models/stat'

# shorthand for require('./auth').fitbit
{fitbit}  = require './auth'
fitbitClient = require("fitbit-js")(fitbit.consumerKey,
fitbit.consumerSecret, fitbit.callbackURL)
moment = require 'moment'


# fixme: refactor to use promises or async library here
# ASYNC hell down below!!!!!!!


module.exports =

  #==========================
  # static assets
  #==========================

  index: (req, res) ->
    # by default express will send index.html on  GET '/'
    # so this is just optional
    # send back splash/landing instead
    # of jsut login/signup
    res.sendfile('index.html')


  #==========================
  # CRUD ops
  #==========================

  # logout helper
  logout: (req, res) ->
    id = req.user._id
    User.findById id, (err, user) ->
      if err
        throw new Error err, ' cannot find user to log'
      if user
        user.lastLoggedIn = Date.now()
        user.save (err) ->
          throw new Error err if err
      req.logout()
      res.redirect '/'

  # get curent user on the fly if need it, should not need this, security issue
  getUser: (req, res) ->
    id = req.params.id
    res.send 401 if id isnt String req.user._id # can only get logged in user
    User.findById id, (err, user) ->
      if err
        throw new Error err, 'User.findOne error '

      if not user
        # user isn't in the db
        res.send 204
      if user
        res.json user

  # get all users here for streams
  allUsersActivity: (req, res) ->
    # define query for search
    query =
      user:
        $ne: req.user._id

    # check for from and to dates and add to query
    yesterday = moment().subtract('days', 1).format 'YYYY-MM-DD'
    dateRange  yesterday, yesterday, query

    # use .populate(), its fucking magic!
    # http://mongoosejs.com/docs/populate.html
    Stats.find(query).populate('user', 'pro username authData.fitbit.avatar')
    .exec (err, stats) ->
      if err
        throw new Error err, 'err users stream'
      else if stats
        res.json stats

  # ===========================
  # query DB to get single user
  # steps
  # ===========================

  userActivity: (req, res) ->
    # define the DB query to get results
    today = moment().subtract('days', 1).format 'YYYY-MM-DD'
    query = user: req.user._id
    dateRange today, today, query
    Stats.find query, (err, stats) ->
      if err
        throw new Error err, 'error getting api/user data'
      else if stats.length
      # if stats, send back reqested range of stats along with user data
        data =
          username: req.user.username
          pic: req.user.authData.fitbit.avatar
          stats: stats[0]
        console.log 'already got data ', data
        res.json data
      else if !stats.length
        # if no stats in db, go to fitbit and get 7 days
        # worth of stats and save to db
        date = moment().subtract('days', 7)

        toDate = moment().subtract('days', 1)
        query =
          'user': req.user._id
          'date': toDate.format 'YYYY-MM-DD'


        while date <= toDate
          # helper function that goes to fitbit and gets a weeks data set
          getDailyActivities req, res, date.format('YYYY-MM-DD'), saveStats
          date = date.add 'days', 1

          # change this to somethig else, this is horrbile, but
          # front end will be looking for null right now
  errorTest: (req, res) ->
    throw new Error 'test error!!!!'

  compare: (req, res) ->
    # used to send back a comparison of current user
    # and any given user's data for 7 days
    # used to populate d3 graphs on back of cards
    compareUser = req.params.userid
    query =
      user: req.user._id

    to = moment().format 'YYYY-MM-DD'
    from = moment().subtract('days', 9).format 'YYYY-MM-DD'

    dateRange from, to, query

    returnJSON = []
    # get current users weeky data set
    Stats.find(query).sort(date: 1).exec (err, stat) ->
      if err
        throw new Error err, 'error gettig logged in user to compare'
      if stat
        data =
          username: req.user.username
          stat: stat
        # collect the current users weekly data
        # FIXME: find a better way to do this, promises
        returnJSON.push data

      query.user = compareUser
      Stats.find(query).populate('user', 'username').sort(date: 1)
      .exec (error, statt) ->
        if err
          throw new Error error, 'finding second user to compare'
        returnJSON.push statt
        res.json returnJSON

  # helper to delete current user
  deleteUser: (req, res) ->
    id = req.user._id
    User.findById id, (err, user) ->
      if err
        throw new Error err, 'could not find user to delete'
      if not user
        # user is not in DB anyways..
        res.send 204
      else
        user.remove (err, user) -> # remove user record
          if err
            throw new Error err, 'could not delete user'
          req.logout()
          res.redirect '/'

  # helper to protect angular routes on client
  loggedIn: (req, res) ->
    res.send if req.isAuthenticated() then req.user else "0"

  #==========================
  # API helpers
  #==========================

dateRange = (dateFrom, dateTo, query) ->
  dateFrom = (if (dateFrom is "-") then undefined else dateFrom)
  dateTo = (if (dateTo is "-") then undefined else dateTo)
  if dateFrom isnt undefined and dateTo isnt undefined
    query.date =
      $gte: dateFrom
      $lte: dateTo
  else
    query.date = $gte: dateFrom  if dateFrom isnt undefined
    query.date = $lte: dateTo  if dateTo isnt undefined

# helper function to get a weeks worth of data from fitbit
getDailyActivities = (req, res, day, cb) ->
  token =
    oauth_token: req.user.authData.fitbit.access_token
    oauth_token_secret: req.user.authData.fitbit.access_token_secret

  fitbitClient.apiCall 'GET', '/user/-/activities/date/'+ day + '.json',
  'token': token, (err, resp, userData) ->
    if err
      throw new Error err, 'error-- routeHelpers -- getDailyActivities'
    stat = new Stats()
    stat.user = req.user._id
    stat.date = day
    stat.steps = userData.summary.steps
    stat.veryActiveMinutes = userData.summary.veryActiveMinutes
    stat.distance = userData.summary.distances[0].distance
    cb stat, req, res

# helper function to save new stats


saveStats = (stat, req, res) ->

  date = moment().subtract('days', 1).format "YYYY-MM-DD"
  stat.save (err) ->
    if err
      throw new Error err, 'error savnig stats'
    console.log 'save new stat for ', stat.date
    if stat.date is moment().subtract('days', 1).format 'YYYY-MM-DD'
      console.log 'date matched', stat.date
      data =
          username: req.user.username
          pic: req.user.authData.fitbit.avatar
          stats: stat
      console.log '====data====', data
      res.json data


