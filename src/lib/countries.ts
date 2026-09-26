import {
  continents,
  countries,
  languages,
  type TCountryCode,
  type TLanguageCode,
} from "countries-list";

export type CountryFacts = {
  code: string;
  name: string;
  nativeName: string;
  capital: string | null;
  continent: string;
  currencies: string[];
  languages: string[];
  callingCodes: string[];
};

/** Country facts for an ISO 3166-1 alpha-2 code, from the MIT-licensed
 * countries-list package. */
export function countryFacts(code: string | null | undefined) {
  if (!code) return null;
  const country = countries[code.toUpperCase() as TCountryCode];
  if (!country) return null;
  return {
    code: code.toUpperCase(),
    name: country.name,
    nativeName: country.native,
    capital: country.capital || null,
    continent: continents[country.continent],
    currencies: country.currency,
    languages: country.languages.map(
      (lang) => languages[lang as TLanguageCode]?.name ?? lang,
    ),
    callingCodes: country.phone.map((phone) => `+${phone}`),
  } satisfies CountryFacts;
}

export function countryName(code: string | null | undefined) {
  if (!code) return null;
  return countries[code.toUpperCase() as TCountryCode]?.name ?? code;
}
