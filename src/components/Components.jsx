import styled from 'styled-components';

export const Container = styled.section`
  background: url('https://s3-alpha-sig.figma.com/img/b08f/00ef/91e8575454d535850cb179707ffb4619?Expires=1636934400&Signature=SDLYDGXpWEiV704j9lfXFYT4c5zjVFLKTU5~-iNnmOWsnoXqR2denUAagUx5oG88pxLQvUedGILdWPDuk09ttewchzAbGTesQUPCOA6h62vXgUPKGGkmq4bskq5p4TuYK46be1MJLNXwFAZK0bW~q5MuDeBGr8zWQTFDkZwA3UhU11yZhJqOXVTi8bkkUYxmMErodzMqxQ8bXkprrT~VUXOUqsAQcAx~iGPGJco0JFR-Fu2musHtsqMy3Nr~KzmzCqbk5Es37AXyHCC5ECGq56phmKrd18MCvwKBLQSTqpi1J2Q0NE5OSNuQlRqXtmQPrcIsIqLFwII3Hx6ozChyOQ__&Key-Pair-Id=APKAINTVSUGEWH5XD5UA');
  background-size: cover;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  min-height: 90vh;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, 'Open Sans', 'Helvetica Neue', sans-serif;
  padding-top: 10vh;
`

export const Button = styled.button`
  font-size: 14px;
  background: ${props => props.black ? "#191A1A" : "#9DF368"};
  color: ${props => props.black ? "#EDF0EB" : "#0F1010"};
  border-radius: 110px;
  width: 371px;
  height: 66px;
  border: none;
  margin: 9px;
  text-align: center;
  &:hover {
    background: ${props => props.black ? "#3E4242" : "#CBF9AF"};
    color: ${props => props.black ? "#EDF0EB" : "#0F1010"};
  }
`

export const Bond = styled.div`
  width: 90%;
  display: flex;
  background: #252727;
  height: 70px;
  align-items: center;
  border-radius: 6px;
  &:hover {
    background: #313535;
    border-radius: 60px;
  }
`

export const BondColumn = styled.div`
  display: flex;
  width: ${props => props.width || "25%"};
  color: #EDF0EB;
  font-size: 14px;
  align-items: center;
  justify-content: center;
`

export const H1Text = styled.div`
  color: ${props => props.white ? "#EDF0EB" : "#1F1F1F"};
  font-size: 80px;
  font-weight: 900;
  font-family: GT Super Text;
  line-height: 110%;
  text-align: center;
`

export const H2Text = styled.div`
  color: ${props => props.white ? "#EDF0EB" : "#1F1F1F"};
  font-size: 64px;
  font-weight: 900;
  font-family: GT Super Text;
  line-height: 118%;
  text-align: center;
`

export const H3Text = styled.div`
  color: ${props => props.white ? "#EDF0EB" : "#1F1F1F"};
  font-size: 52px;
  font-weight: 900;
  font-family: GT Super Text;
  line-height: 118%;
  text-align: center;
`

export const H4Text = styled.div`
  color: ${props => props.white ? "#EDF0EB" : "#1F1F1F"};
  font-size: 40px;
  font-weight: 900;
  font-family: GT Super Text;
  text-align: center;
`

export const H5Text = styled.div`
  color: ${props => props.white ? "#EDF0EB" : "#1F1F1F"};
  font-size: 28px;
  font-weight: 900;
  font-family: GT Super Text;
  text-align: center;
`

export const BodyText = styled.p`
  font-size: 24px;
  line-height: 140%;
  color: ${props => props.white ? "#EDF0EB" : "#1F1F1F"};
  margin-bottom: 101px;
  max-width: 650px;
  text-align: center;
`

export const CryptoIcon = styled.img`
  padding-left: 15px;
  padding-right: 15px;
`

export const Dropdown = styled.div`
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  height: 44px;
  width: 312px;
  background: #252727;
  color: #7D8282;
  border-radius: 40px;
  font-size: 14px;
  padding: 0 20px 0 10px;
  &:hover {
    color: #EDF0EB;
  }
`

export const StyledSVG = styled.svg`
  path {
    fill: #7D8282;
  } 
  ${Dropdown}:hover & path {
    fill: #EDF0EB;
  } 
`