-- 1. Find all players in the database who played at Vanderbilt University. Create a list showing each player's first and last names as well as the total salary they earned in the major leagues. Sort this list in descending order by the total salary earned. Which Vanderbilt player earned the most money in the majors?

WITH 
earnings AS(
	SELECT  playerid,
			SUM(salary) as big_league_pay 
	FROM salaries
	GROUP BY playerid
),
vandy AS(
	SELECT DISTINCT(playerid)
	FROM collegeplaying
	WHERE schoolid = 'vandy'
)
SELECT playerid, 
	   p.namefirst,
	   p.namelast, 
	   COALESCE(big_league_pay, 0)::NUMERIC::MONEY as total_pay
FROM people as p
INNER JOIN vandy
USING(playerid)
LEFT JOIN earnings
USING(playerid)
ORDER BY total_pay DESC;

-- 2. Using the fielding table, group players into three groups based on their position: label players with position OF as "Outfield", those with position "SS", "1B", "2B", and "3B" as "Infield", and those with position "P" or "C" as "Battery". Determine the number of putouts made by each of these three groups in 2016.

SELECT  
		CASE WHEN pos IN  ('SS','1B','2B','3B') THEN 'Infield'
			 WHEN pos IN ('P','C') THEN 'Battery'
			 ELSE 'Outfield'
			 END AS position_category,
		SUM(po) AS total_putouts_2016
FROM fielding
WHERE yearid = 2016
GROUP BY position_category 
ORDER BY total_putouts_2016 DESC;


-- 3. Find the average number of strikeouts per game by decade since 1920. Round the numbers you report to 2 decimal places. Do the same for home runs per game. Do you see any trends? (Hint: For this question, you might find it helpful to look at the **generate_series** function (https://www.postgresql.org/docs/9.1/functions-srf.html). If you want to see an example of this in action, check out this DataCamp video: https://campus.datacamp.com/courses/exploratory-data-analysis-in-sql/summarizing-and-aggregating-numeric-data?ex=6)
SELECT *
FROM(
	-- Strikeouts
	WITH games_by_decade AS (
	  SELECT 
		yearid, 
		FLOOR(yearid / 10) * 10 AS decade, 
		SUM(SO) AS total_strikeouts, 
		SUM(G) AS total_games
	  FROM pitching
	  GROUP BY decade, yearid
	), avg_strikeouts_per_game AS (
	  SELECT 
		decade, 
		SUM(total_strikeouts) / SUM(total_games) AS avg_strikeouts_per_game
	  FROM games_by_decade
	  GROUP BY decade
	)
	SELECT 
	  decade, 
	  ROUND(avg_strikeouts_per_game, 2) AS avg_strikeouts_per_game
	FROM avg_strikeouts_per_game
	ORDER BY decade
	
) AS strikeouts

INNER JOIN (
	-- Homeruns
	WITH games_by_decade AS (
	  SELECT 
		yearID, 
		FLOOR(yearID / 10) * 10 AS decade, 
		SUM(HR) AS total_homers, 
		SUM(G) AS total_games
	  FROM Batting
	  GROUP BY decade, yearID
	), avg_homers_per_game AS (
	  SELECT 
		decade, 
		SUM(total_homers) / SUM(total_games) AS avg_homers_per_game
	  FROM games_by_decade
	  GROUP BY decade
	)
	SELECT 
	  decade, 
	  ROUND(avg_homers_per_game, 2) AS avg_homers_per_game
	FROM avg_homers_per_game
	ORDER BY decade
) AS homeruns

USING(decade)
WHERE decade >= 1920;


-- 4. Find the player who had the most success stealing bases in 2016, where __success__ is measured as the percentage of stolen base attempts which are successful. (A stolen base attempt results either in a stolen base or being caught stealing.) Consider only players who attempted _at least_ 20 stolen bases. Report the players' names, number of stolen bases, number of attempts, and stolen base percentage.

SELECT 	playerid, 
		namefirst, 
		namelast, 
		SUM(sb) AS total_sb,
		SUM(cs) AS total_cs, 
		ROUND((SUM(sb)::NUMERIC / (SUM(sb) + SUM(cs))::NUMERIC)*100,2) AS percentage_successful_sb
FROM people
INNER JOIN batting 
USING(playerid)
WHERE yearid = 2016
GROUP BY playerid
HAVING SUM(sb) >= 20
ORDER BY percentage_successful_sb DESC;


-- 5. From 1970 to 2016, what is the largest number of wins for a team that did not win the world series? What is the smallest number of wins for a team that did win the world series? Doing this will probably result in an unusually small number of wins for a world series champion; determine why this is the case. Then redo your query, excluding the problem year. 
SELECT name, yearid, w, wswin
FROM teams
WHERE yearid BETWEEN 1970 AND 2016 
		AND wswin = 'N'
ORDER BY w DESC
LIMIT 1; -- "Seattle Mariners" 2001 with 116 wins. 


SELECT name, yearid, w, wswin
FROM teams
WHERE yearid BETWEEN 1970 AND 2016 
		AND wswin = 'Y'
ORDER BY w 
LIMIT 1; -- "Los Angeles Dodgers" 1981 with 63 wins.

-- There was a 51 day strike in 1981 MLB season that canceled games, thats why the LA DOdgers advanceed to the WS with only 63 wins in the regular season. 

-- Excluding 1981
SELECT name, yearid, w, wswin
FROM teams
WHERE yearid BETWEEN 1970 AND 2016 
		AND yearid != 1981
		AND wswin = 'Y'
ORDER BY w 
LIMIT 1; -- "St. Louis Cardinals" in 2006 with 83 wins. 

-- How often from 1970 to 2016 was it the case that a team with the most wins also won the world series? What percentage of the time?

WITH
wins_per_team_per_season AS (
	SELECT yearid, 
		 teamid, 
		 SUM(w) AS team_wins
	FROM teams
	GROUP BY yearid, teamid
), 
most_wins_per_season AS (
	SELECT yearid, 
		 MAX(team_wins) AS max_wins_for_the_year
	FROM wins_per_team_per_season
	WHERE yearID BETWEEN 1970 AND 2016
	GROUP BY yearid
), 
ws_winners AS (
	SELECT yearid, teamid AS teamid_wswinner 
	FROM teams
	WHERE wswin = 'Y'
)
SELECT ROUND((SUM(CASE WHEN team_wins = max_wins_for_the_year AND teamid = teamid_wswinner THEN 1
			 		   ELSE 0 END
				 )/COUNT(*)::NUMERIC
			 )*100, 2) AS percentage_of_most_wins_and_ws
FROM wins_per_team_per_season as wptps
INNER JOIN most_wins_per_season as mwps
USING(yearid)
INNER JOIN ws_winners as ws
USING(yearid);


-- 6. Which managers have won the TSN Manager of the Year award in both the National League (NL) and the American League (AL)? Give their full name and the teams that they were managing when they won the award.
WITH great_managers AS (
	SELECT 
	 	playerid
	FROM awardsmanagers
	WHERE awardid LIKE '%TSN%'
	GROUP BY playerid
	HAVING COUNT(DISTINCT lgid) > 1
),
great_managers_years AS (
	SELECT *
	FROM awardsmanagers
	WHERE playerid IN (SELECT playerid FROM great_managers)
		AND awardid LIKE '%TSN%'

)

SELECT namefirst, namelast, gmy.yearid, gmy.lgid, teamid, name
FROM great_managers_years AS gmy
INNER JOIN people
USING(playerid)
LEFT JOIN managers
USING(playerid, yearid, lgid)
LEFT JOIN teams
USING(yearid, lgid, teamid)

-- 7. Which pitcher was the least efficient in 2016 in terms of salary / strikeouts? Only consider pitchers who started at least 10 games (across all teams). Note that pitchers often play for more than one team in a season, so be sure that you are counting all stats for each player.

-- 8. Find all players who have had at least 3000 career hits. Report those players' names, total number of hits, and the year they were inducted into the hall of fame (If they were not inducted into the hall of fame, put a null in that column.) Note that a player being inducted into the hall of fame is indicated by a 'Y' in the **inducted** column of the halloffame table.

-- 9. Find all players who had at least 1,000 hits for two different teams. Report those players' full names.

-- 10. Find all players who hit their career highest number of home runs in 2016. Consider only players who have played in the league for at least 10 years, and who hit at least one home run in 2016. Report the players' first and last names and the number of home runs they hit in 2016.

-- After finishing the above questions, here are some open-ended questions to consider.
