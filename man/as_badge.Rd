% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/menu-item.R
\name{as_badge}
\alias{as_badge}
\title{Generates badge icons}
\usage{
as_badge(badge = NULL)
}
\arguments{
\item{badge}{characters, \code{"shiny.tag"} object or \code{NULL}}
}
\value{
'HTML' tags
}
\description{
Usually used along with \code{\link{card}},
\code{\link{card2}}, and \code{\link{card_tabset}}. See \code{tools}
parameters in these functions accordingly.
}
\details{
When \code{badge} is \code{NULL} or empty, then \code{as_badge}
returns empty strings. When \code{badge} is a \code{"shiny.tag"} object,
then 'HTML' class \code{'right'} and \code{'badge'} will be appended.
When \code{badge} is a string, it should follow the syntax of
\code{"message|class"}. The text before \code{"|"} will be the badge
message, and the text after the \code{"|"} becomes the class string.
}
\examples{

# Basic usage
as_badge("New")

# Add class `bg-red` and `no-padding`
as_badge("New|bg-red no-padding")


}
